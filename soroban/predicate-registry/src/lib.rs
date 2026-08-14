#![no_std]

mod attesters;
mod policy;
mod types;
mod validation;

use soroban_sdk::{
    contract, contractimpl, symbol_short, Address, BytesN, Env, String, Symbol, Vec,
};

pub use types::{Attestation, RegistryError, Statement};

// Storage keys
const OWNER: Symbol = soroban_sdk::symbol_short!("owner");
const PENDING_OWNER: Symbol = soroban_sdk::symbol_short!("pnd_own");

#[contract]
pub struct PredicateRegistryContract;

#[contractimpl]
impl PredicateRegistryContract {
    /// Initialize the registry with an owner address.
    ///
    /// # Arguments
    ///
    /// * `owner` - Address with administrative privileges. Can register and
    ///   deregister attesters, and propose a new owner via the two-step
    ///   `transfer_ownership` / `accept_ownership` flow.
    pub fn __constructor(e: &Env, owner: Address) {
        e.storage().instance().set(&OWNER, &owner);
    }

    /// Return the contract owner.
    pub fn owner(e: &Env) -> Address {
        e.storage().instance().get(&OWNER).unwrap()
    }

    /// Propose a new owner. Only the current owner may call this.
    /// The new owner must call `accept_ownership` to finalize the transfer.
    /// This two-step pattern mirrors EVM's Ownable2StepUpgradeable, preventing
    /// accidental transfers to wrong addresses.
    pub fn transfer_ownership(
        e: &Env,
        current_owner: Address,
        new_owner: Address,
    ) -> Result<(), RegistryError> {
        require_owner(e, &current_owner)?;
        e.storage().instance().set(&PENDING_OWNER, &new_owner);
        #[allow(deprecated)]
        e.events().publish(
            (symbol_short!("owner"), symbol_short!("propose")),
            (current_owner, new_owner),
        );
        Ok(())
    }

    /// Accept a pending ownership transfer. Only the pending owner may call this.
    pub fn accept_ownership(e: &Env, new_owner: Address) -> Result<(), RegistryError> {
        let pending: Address = e
            .storage()
            .instance()
            .get(&PENDING_OWNER)
            .ok_or(RegistryError::Unauthorized)?;
        if new_owner != pending {
            return Err(RegistryError::Unauthorized);
        }
        new_owner.require_auth();

        let old_owner: Address = e.storage().instance().get(&OWNER).unwrap();
        e.storage().instance().set(&OWNER, &new_owner);
        e.storage().instance().remove(&PENDING_OWNER);
        #[allow(deprecated)]
        e.events().publish(
            (symbol_short!("owner"), symbol_short!("transfer")),
            (old_owner, new_owner),
        );
        Ok(())
    }

    /// Return the pending owner, if any.
    pub fn pending_owner(e: &Env) -> Option<Address> {
        e.storage().instance().get(&PENDING_OWNER)
    }

    /// Register a new attester. Only the contract owner may call this.
    pub fn register_attester(
        e: &Env,
        owner: Address,
        attester: BytesN<32>,
    ) -> Result<(), RegistryError> {
        require_owner(e, &owner)?;
        attesters::register(e, &attester)
    }

    /// Deregister an attester using swap-and-pop. Only the contract owner may call this.
    pub fn deregister_attester(
        e: &Env,
        owner: Address,
        attester: BytesN<32>,
    ) -> Result<(), RegistryError> {
        require_owner(e, &owner)?;
        attesters::deregister(e, &attester)
    }

    /// Check whether an attester is currently registered.
    pub fn is_attester_registered(e: &Env, attester: BytesN<32>) -> bool {
        attesters::is_registered(e, &attester)
    }

    /// Return all registered attesters.
    pub fn get_registered_attesters(e: &Env) -> Vec<BytesN<32>> {
        attesters::get_all(e)
    }

    /// Set the policy ID for the calling address.
    pub fn set_policy_id(e: &Env, caller: Address, policy_id: String) {
        policy::set(e, &caller, &policy_id);
    }

    /// Get the policy ID for a client address.
    pub fn get_policy_id(e: &Env, client: Address) -> String {
        policy::get(e, &client)
    }

    /// Compute SHA-256 hash of a statement for attester signing.
    /// This is the "hashStatementWithExpiry" equivalent — attesters sign this hash.
    ///
    /// The digest is bound to the host network, read from the ledger rather than
    /// supplied by the caller, so an attestation is only valid on the chain it was
    /// signed for.
    pub fn hash_statement(e: &Env, statement: Statement) -> BytesN<32> {
        validation::compute_hash(e, &statement)
    }

    /// Validate an attestation against a statement.
    ///
    /// The `caller` parameter implements the hashStatementSafe pattern:
    /// it replaces `statement.target` with the actual caller address before
    /// verifying the signature, preventing cross-contract replay attacks.
    /// In Soroban, the calling contract should pass `e.current_contract_address()`.
    pub fn validate_attestation(
        e: &Env,
        statement: Statement,
        attestation: Attestation,
        caller: Address,
    ) -> Result<bool, RegistryError> {
        validation::validate(e, &statement, &attestation, &caller)
    }

    /// Replace the registry's WASM bytecode in place. Only the owner may call this.
    /// The contract address and all storage (owner, attesters, policies, spent UUIDs)
    /// are preserved; only the executable code changes.
    ///
    /// `new_wasm_hash` is the SHA-256 hash of an already-uploaded contract WASM
    /// (see `stellar contract upload`).
    pub fn upgrade(
        e: &Env,
        owner: Address,
        new_wasm_hash: BytesN<32>,
    ) -> Result<(), RegistryError> {
        require_owner(e, &owner)?;
        e.deployer()
            .update_current_contract_wasm(new_wasm_hash.clone());
        #[allow(deprecated)]
        e.events()
            .publish((symbol_short!("upgrade"),), new_wasm_hash);
        Ok(())
    }
}

/// Internal helper: require that `caller` is the stored owner.
pub(crate) fn require_owner(e: &Env, caller: &Address) -> Result<(), RegistryError> {
    let owner: Address = e
        .storage()
        .instance()
        .get(&OWNER)
        .ok_or(RegistryError::NotInitialized)?;
    if *caller != owner {
        return Err(RegistryError::Unauthorized);
    }
    caller.require_auth();
    Ok(())
}

#[cfg(test)]
mod test {
    extern crate std;

    use soroban_sdk::{testutils::Address as _, testutils::Ledger, Address, BytesN, Env};

    use super::*;
    use crate::types::{Attestation, Statement};

    // Import the crate's own compiled WASM so the test can upload it and
    // upgrade the registry to itself (proves the upgrade path + storage survival).
    // Requires: stellar contract build --package predicate-registry
    // (builds to wasm32v1-none, which the soroban host validator accepts)
    mod registry_wasm {
        soroban_sdk::contractimport!(
            file = "../target/wasm32v1-none/release/predicate_registry.wasm"
        );
    }

    fn setup(e: &Env) -> (Address, PredicateRegistryContractClient<'_>) {
        let owner = Address::generate(e);
        let address = e.register(PredicateRegistryContract, (owner.clone(),));
        let client = PredicateRegistryContractClient::new(e, &address);
        (owner, client)
    }

    fn generate_attester_key(e: &Env) -> BytesN<32> {
        BytesN::from_array(e, &[1u8; 32])
    }

    fn generate_attester_key_2(e: &Env) -> BytesN<32> {
        BytesN::from_array(e, &[2u8; 32])
    }

    #[test]
    fn test_register_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let attester = generate_attester_key(&e);

        client.register_attester(&owner, &attester);

        assert!(client.is_attester_registered(&attester));
        let attesters = client.get_registered_attesters();
        assert_eq!(attesters.len(), 1);
        assert_eq!(attesters.get(0).unwrap(), attester);
    }

    #[test]
    fn test_deregister_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let attester = generate_attester_key(&e);

        client.register_attester(&owner, &attester);
        client.deregister_attester(&owner, &attester);

        assert!(!client.is_attester_registered(&attester));
        assert_eq!(client.get_registered_attesters().len(), 0);
    }

    #[test]
    fn test_deregister_swap_and_pop() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let a1 = generate_attester_key(&e);
        let a2 = generate_attester_key_2(&e);

        client.register_attester(&owner, &a1);
        client.register_attester(&owner, &a2);
        client.deregister_attester(&owner, &a1);

        assert!(!client.is_attester_registered(&a1));
        assert!(client.is_attester_registered(&a2));
        let attesters = client.get_registered_attesters();
        assert_eq!(attesters.len(), 1);
        assert_eq!(attesters.get(0).unwrap(), a2);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #2)")]
    fn test_register_duplicate_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let attester = generate_attester_key(&e);

        client.register_attester(&owner, &attester);
        client.register_attester(&owner, &attester);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #3)")]
    fn test_deregister_unregistered_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let attester = generate_attester_key(&e);

        client.deregister_attester(&owner, &attester);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #1)")]
    fn test_non_owner_cannot_register() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);
        let not_owner = Address::generate(&e);
        let attester = generate_attester_key(&e);

        client.register_attester(&not_owner, &attester);
    }

    #[test]
    fn test_set_and_get_policy() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);
        let caller = Address::generate(&e);
        let policy = soroban_sdk::String::from_str(&e, "x-a1b2c3d4e5f6g7h8");

        client.set_policy_id(&caller, &policy);
        assert_eq!(client.get_policy_id(&caller), policy);
    }

    #[test]
    fn test_policy_default_empty() {
        let e = Env::default();
        let (_owner, client) = setup(&e);
        let caller = Address::generate(&e);

        let policy = client.get_policy_id(&caller);
        assert_eq!(policy, soroban_sdk::String::from_str(&e, ""));
    }

    #[test]
    fn test_update_policy() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);
        let caller = Address::generate(&e);

        let p1 = soroban_sdk::String::from_str(&e, "policy-1");
        let p2 = soroban_sdk::String::from_str(&e, "policy-2");

        client.set_policy_id(&caller, &p1);
        client.set_policy_id(&caller, &p2);
        assert_eq!(client.get_policy_id(&caller), p2);
    }

    // --- Ownership transfer tests ---

    #[test]
    fn test_two_step_ownership_transfer() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let new_owner = Address::generate(&e);

        // Step 1: propose
        client.transfer_ownership(&owner, &new_owner);
        assert_eq!(client.owner(), owner); // still the old owner
        assert_eq!(client.pending_owner(), Some(new_owner.clone()));

        // Step 2: accept
        client.accept_ownership(&new_owner);
        assert_eq!(client.owner(), new_owner);
        assert_eq!(client.pending_owner(), None);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #1)")]
    fn test_non_owner_cannot_propose_transfer() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);
        let attacker = Address::generate(&e);
        let new_owner = Address::generate(&e);

        client.transfer_ownership(&attacker, &new_owner);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #1)")]
    fn test_wrong_address_cannot_accept_ownership() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let new_owner = Address::generate(&e);
        let attacker = Address::generate(&e);

        client.transfer_ownership(&owner, &new_owner);
        client.accept_ownership(&attacker); // wrong address
    }

    // --- Validation tests ---

    /// Helper: create an ed25519 signing key and return (signing_key, pub_key_bytes)
    fn generate_ed25519_keypair(e: &Env) -> (ed25519_dalek::SigningKey, BytesN<32>) {
        use ed25519_dalek::SigningKey;
        use rand::rngs::OsRng;
        let sk = SigningKey::generate(&mut OsRng);
        let pk_bytes = sk.verifying_key().to_bytes();
        (sk, BytesN::from_array(e, &pk_bytes))
    }

    /// Helper: sign a hash (BytesN<32>) with an ed25519 signing key, returning BytesN<64>
    fn sign_hash(e: &Env, sk: &ed25519_dalek::SigningKey, hash: &BytesN<32>) -> BytesN<64> {
        use ed25519_dalek::Signer;
        let sig = sk.sign(&hash.to_array());
        BytesN::from_array(e, &sig.to_bytes())
    }

    #[test]
    fn test_validate_attestation_happy_path() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        let (sk, pub_key) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key);

        let statement = Statement {
            uuid: soroban_sdk::String::from_str(&e, "uuid-happy"),
            msg_sender: Address::generate(&e),
            target: client.address.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(&e, &[0xAAu8; 32]),
            policy: soroban_sdk::String::from_str(&e, "x-test"),
            expiration: e.ledger().timestamp() + 600,
        };

        let hash = client.hash_statement(&statement);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        let result = client.validate_attestation(&statement, &attestation, &client.address);
        assert!(result);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #4)")]
    fn test_validate_expired_attestation() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        let (sk, pub_key) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key);

        // Set ledger timestamp to something > 0 so expiration=0 is expired
        e.ledger().set_timestamp(100);

        let statement = Statement {
            uuid: soroban_sdk::String::from_str(&e, "uuid-expired"),
            msg_sender: Address::generate(&e),
            target: client.address.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(&e, &[0u8; 32]),
            policy: soroban_sdk::String::from_str(&e, "x-test"),
            expiration: 0,
        };

        let hash = client.hash_statement(&statement);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: 0,
            attester: pub_key,
            signature,
        };

        client.validate_attestation(&statement, &attestation, &client.address);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #5)")]
    fn test_validate_uuid_replay() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        let (sk, pub_key) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key);

        let statement = Statement {
            uuid: soroban_sdk::String::from_str(&e, "uuid-replay"),
            msg_sender: Address::generate(&e),
            target: client.address.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(&e, &[0u8; 32]),
            policy: soroban_sdk::String::from_str(&e, "x-test"),
            expiration: e.ledger().timestamp() + 600,
        };

        let hash = client.hash_statement(&statement);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        // First call succeeds
        client.validate_attestation(&statement, &attestation, &client.address);
        // Second call should fail with UuidAlreadyUsed
        client.validate_attestation(&statement, &attestation, &client.address);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #6)")]
    fn test_validate_uuid_mismatch() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        let (sk, pub_key) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key);

        let statement = Statement {
            uuid: soroban_sdk::String::from_str(&e, "uuid-A"),
            msg_sender: Address::generate(&e),
            target: client.address.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(&e, &[0u8; 32]),
            policy: soroban_sdk::String::from_str(&e, "x-test"),
            expiration: e.ledger().timestamp() + 600,
        };

        let hash = client.hash_statement(&statement);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: soroban_sdk::String::from_str(&e, "uuid-B"), // mismatch
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        client.validate_attestation(&statement, &attestation, &client.address);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #7)")]
    fn test_validate_expiration_mismatch() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        let (sk, pub_key) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key);

        let statement = Statement {
            uuid: soroban_sdk::String::from_str(&e, "uuid-exp"),
            msg_sender: Address::generate(&e),
            target: client.address.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(&e, &[0u8; 32]),
            policy: soroban_sdk::String::from_str(&e, "x-test"),
            expiration: e.ledger().timestamp() + 600,
        };

        let hash = client.hash_statement(&statement);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration + 100, // mismatch
            attester: pub_key,
            signature,
        };

        client.validate_attestation(&statement, &attestation, &client.address);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #3)")]
    fn test_validate_unregistered_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);

        let (sk, pub_key) = generate_ed25519_keypair(&e);
        // NOT registering attester

        let statement = Statement {
            uuid: soroban_sdk::String::from_str(&e, "uuid-unreg"),
            msg_sender: Address::generate(&e),
            target: client.address.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(&e, &[0u8; 32]),
            policy: soroban_sdk::String::from_str(&e, "x-test"),
            expiration: e.ledger().timestamp() + 600,
        };

        let hash = client.hash_statement(&statement);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        client.validate_attestation(&statement, &attestation, &client.address);
    }

    /// Build a statement whose `target` is already the caller, so `hash_statement`
    /// returns exactly the digest `validate_attestation` recomputes. That isolates
    /// the domain-separation checks below from the hashStatementSafe substitution.
    fn caller_bound_statement(e: &Env, uuid: &str, caller: &Address) -> Statement {
        Statement {
            uuid: soroban_sdk::String::from_str(e, uuid),
            msg_sender: Address::generate(e),
            target: caller.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(e, &[0u8; 32]),
            policy: soroban_sdk::String::from_str(e, "x-test"),
            expiration: e.ledger().timestamp() + 600,
        }
    }

    /// The network is read from the ledger rather than supplied by the caller, so
    /// the digest changes with the chain the registry is running on. Deliberately
    /// *not* asserted here: that two registry instances on the same network hash
    /// differently. The registry address is not part of the preimage — see the
    /// rationale on `validation::compute_hash`.
    #[test]
    fn test_digest_is_bound_to_network_id() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);

        let caller = Address::generate(&e);
        let statement = caller_bound_statement(&e, "uuid-per-network", &caller);

        let hash = client.hash_statement(&statement);
        e.ledger().set_network_id([7u8; 32]);
        assert_ne!(hash, client.hash_statement(&statement));
    }

    /// An attestation signed on one chain cannot be presented on another, even to
    /// the registry deployed at the same address.
    #[test]
    #[should_panic(expected = "Error(Crypto, InvalidInput)")]
    fn test_attestation_from_another_network_is_rejected() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        let (sk, pub_key) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key);

        let caller = Address::generate(&e);
        let statement = caller_bound_statement(&e, "uuid-cross-network", &caller);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature: sign_hash(&e, &sk, &client.hash_statement(&statement)),
        };

        e.ledger().set_network_id([7u8; 32]);
        client.validate_attestation(&statement, &attestation, &caller);
    }

    // --- Golden vector ---
    //
    // Every other test here asks the contract for a digest and then signs it, so
    // the contract is only ever checked against itself: swapping the order of the
    // appends in `compute_hash`, or renaming a `Statement` field — `#[contracttype]`
    // uses field names as ScMap keys — silently changes the wire format while every
    // test still passes. A plain refactor can therefore break every attestation the
    // API has already signed.
    //
    // The constants below are the fix. They come from `scripts/golden-vector.js`, a
    // third implementation hand-rolled from the XDR spec that shares no code with
    // this contract, so nothing but a byte-identical layout satisfies them. Pinning
    // the same vector in the Go signer locks both sides to one value instead of each
    // agreeing with itself.
    //
    // If a change here is deliberate, regenerate with that script and update both
    // sides in the same rollout — the digest changing invalidates every attestation
    // already issued.

    /// `sha256("Test SDF Network ; September 2015")`
    const GV_NETWORK_ID: &str = "cee0302d59844d32bdca915c8203dd44b33fbb7edc19051ea37abedf28ecd472";
    /// Account (`G…`) strkey over a payload of 32 `0x11` bytes.
    const GV_MSG_SENDER: &str = "GAIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCF6M";
    /// Contract (`C…`) strkey over a payload of 32 `0x22` bytes.
    const GV_TARGET: &str = "CARCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEIRCEVQO";
    const GV_UUID: &str = "3f2504e0-4f89-11d3-9a0c-0305e82c3301";
    const GV_POLICY: &str = "x-golden-vector-policy";
    const GV_ENCODED_SIG_AND_ARGS: [u8; 8] = [1, 2, 3, 4, 5, 6, 7, 8];
    const GV_MSG_VALUE: i128 = 1_000_000;
    /// 2026-01-01T00:00:00Z
    const GV_EXPIRATION: u64 = 1_767_225_600;

    /// `sha256(XDR(ScVal::Bytes(GV_NETWORK_ID)) ++ XDR(statement))`
    const GV_DIGEST: &str = "f84da64cd98e8f705c1afa37a268a7205e25bf2a71f43a6766b79292094f5cb2";
    /// ed25519 public key for a signing seed of 32 `0x33` bytes.
    const GV_ATTESTER_PK: &str = "17cb79fb2b4120f2b1ec65e4198d6e08b28e813feb01e4a400839b85e18080ce";
    /// That key's signature over `GV_DIGEST`.
    const GV_SIGNATURE: &str = "5cd8dd1d7ce37284f17f951d7001a2f3b5927f6325d50550b87bf0396da46c72243ed72003b1ecfa76c9cf1800e9ca1551343186231875211ec46a34810a1500";

    fn unhex<const N: usize>(h: &str) -> [u8; N] {
        let bytes = h.as_bytes();
        assert_eq!(bytes.len(), N * 2, "hex literal is the wrong length");
        let mut out = [0u8; N];
        for (i, byte) in out.iter_mut().enumerate() {
            let digit = |c: u8| (c as char).to_digit(16).expect("non-hex digit") as u8;
            *byte = (digit(bytes[i * 2]) << 4) | digit(bytes[i * 2 + 1]);
        }
        out
    }

    fn to_hex(bytes: &[u8]) -> std::string::String {
        let mut out = std::string::String::new();
        for b in bytes {
            out.push_str(&std::format!("{:02x}", b));
        }
        out
    }

    /// The statement the golden digest was computed over. `target` is the address
    /// the test passes as `caller`, so `validate_attestation`'s hashStatementSafe
    /// substitution is a no-op and it hashes exactly this.
    fn golden_statement(e: &Env) -> Statement {
        Statement {
            uuid: soroban_sdk::String::from_str(e, GV_UUID),
            msg_sender: Address::from_str(e, GV_MSG_SENDER),
            target: Address::from_str(e, GV_TARGET),
            msg_value: GV_MSG_VALUE,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(e, &GV_ENCODED_SIG_AND_ARGS),
            policy: soroban_sdk::String::from_str(e, GV_POLICY),
            expiration: GV_EXPIRATION,
        }
    }

    /// The digest for a fixed statement on a fixed network must equal a value this
    /// contract did not produce.
    #[test]
    fn test_golden_vector_digest() {
        let e = Env::default();
        e.mock_all_auths();
        e.ledger().set_network_id(unhex::<32>(GV_NETWORK_ID));
        let (_owner, client) = setup(&e);

        let digest = client.hash_statement(&golden_statement(&e));

        assert_eq!(to_hex(&digest.to_array()), GV_DIGEST);
    }

    /// The same vector through the real verification path: an externally produced
    /// ed25519 signature over `GV_DIGEST` must satisfy `validate_attestation`. This
    /// covers the ed25519 call too, not just the hashing.
    #[test]
    fn test_golden_vector_signature() {
        let e = Env::default();
        e.mock_all_auths();
        e.ledger().set_network_id(unhex::<32>(GV_NETWORK_ID));
        let (owner, client) = setup(&e);

        let attester = BytesN::from_array(&e, &unhex::<32>(GV_ATTESTER_PK));
        client.register_attester(&owner, &attester);

        let statement = golden_statement(&e);
        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester,
            signature: BytesN::from_array(&e, &unhex::<64>(GV_SIGNATURE)),
        };

        // `caller` is the statement's own target, so the digest verified here is
        // GV_DIGEST unchanged.
        let caller = Address::from_str(&e, GV_TARGET);
        assert!(client.validate_attestation(&statement, &attestation, &caller));
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #1)")]
    fn test_non_owner_cannot_upgrade() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);
        let not_owner = Address::generate(&e);
        // Any 32-byte hash — the Unauthorized check fires before the WASM is touched.
        let fake_hash = BytesN::from_array(&e, &[9u8; 32]);

        client.upgrade(&not_owner, &fake_hash);
    }

    #[test]
    fn test_upgrade_happy_path_preserves_storage() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        // Seed storage before the upgrade.
        let attester = generate_attester_key(&e);
        client.register_attester(&owner, &attester);
        assert!(client.is_attester_registered(&attester));

        // Upload the crate's own WASM and upgrade to it.
        let wasm_hash = e.deployer().upload_contract_wasm(registry_wasm::WASM);
        client.upgrade(&owner, &wasm_hash);

        // Same address, same storage after the bytecode swap.
        assert_eq!(client.owner(), owner);
        assert!(client.is_attester_registered(&attester));
    }

    #[test]
    #[should_panic(expected = "Error(Crypto, InvalidInput)")] // ed25519_verify panics on bad signature
    fn test_validate_invalid_signature() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        // Register attester A
        let (sk_a, pub_key_a) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key_a);

        // Also register attester B (so it's registered) but sign with A's key
        let (_sk_b, pub_key_b) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key_b);

        let statement = Statement {
            uuid: soroban_sdk::String::from_str(&e, "uuid-badsig"),
            msg_sender: Address::generate(&e),
            target: client.address.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(&e, &[0u8; 32]),
            policy: soroban_sdk::String::from_str(&e, "x-test"),
            expiration: e.ledger().timestamp() + 600,
        };

        let hash = client.hash_statement(&statement);
        // Sign with key A but claim attester is key B
        let signature = sign_hash(&e, &sk_a, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key_b, // wrong attester for this signature
            signature,
        };

        client.validate_attestation(&statement, &attestation, &client.address);
    }

    #[test]
    fn test_uuid_marker_ttl_extended_to_max() {
        use soroban_sdk::testutils::storage::Persistent as _;

        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        let (sk, pub_key) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key);

        let statement = Statement {
            uuid: soroban_sdk::String::from_str(&e, "uuid-ttl"),
            msg_sender: Address::generate(&e),
            target: client.address.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(&e, &[0u8; 32]),
            policy: soroban_sdk::String::from_str(&e, "x-test"),
            expiration: e.ledger().timestamp() + 600,
        };

        let hash = client.hash_statement(&statement);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        client.validate_attestation(&statement, &attestation, &client.address);

        // The replay marker must be extended to the network max TTL, not a fixed
        // ~30-day window that could be archived while an attestation is still valid.
        let uuid_key = (symbol_short!("uuid"), statement.uuid.clone());
        e.as_contract(&client.address, || {
            let ttl = e.storage().persistent().get_ttl(&uuid_key);
            let max_ttl = e.storage().max_ttl();
            assert_eq!(ttl, max_ttl);
        });
    }
}
