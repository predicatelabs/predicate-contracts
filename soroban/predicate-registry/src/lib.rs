#![no_std]
//! Verifies attester-signed [`Statement`]s on behalf of integrating contracts.
//!
//! The registry cannot see the call it authorizes — that runs in the integrating
//! contract's own invocation. It establishes two fields itself, `target` and the
//! network, and trusts the rest as passed. Integrators must therefore build those
//! from the call being authorized; `predicate-client` exists to make that the
//! path of least resistance. See [`PredicateRegistryContract::validate_attestation`].

mod attesters;
mod policy;
mod types;
mod validation;

use soroban_sdk::{
    contract, contractimpl, symbol_short, Address, BytesN, Env, String, Symbol, Vec,
};

pub use types::{Attestation, RegistryError, Statement};

const OWNER: Symbol = soroban_sdk::symbol_short!("owner");
const PENDING_OWNER: Symbol = soroban_sdk::symbol_short!("pnd_own");

#[contract]
pub struct PredicateRegistryContract;

#[contractimpl]
impl PredicateRegistryContract {
    pub fn __constructor(e: &Env, owner: Address) {
        e.storage().instance().set(&OWNER, &owner);
    }

    pub fn owner(e: &Env) -> Address {
        e.storage().instance().get(&OWNER).unwrap()
    }

    /// Proposes only; `new_owner` must call `accept_ownership` to take effect.
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

    pub fn pending_owner(e: &Env) -> Option<Address> {
        e.storage().instance().get(&PENDING_OWNER)
    }

    pub fn register_attester(
        e: &Env,
        owner: Address,
        attester: BytesN<32>,
    ) -> Result<(), RegistryError> {
        require_owner(e, &owner)?;
        attesters::register(e, &attester)
    }

    pub fn deregister_attester(
        e: &Env,
        owner: Address,
        attester: BytesN<32>,
    ) -> Result<(), RegistryError> {
        require_owner(e, &owner)?;
        attesters::deregister(e, &attester)
    }

    pub fn is_attester_registered(e: &Env, attester: BytesN<32>) -> bool {
        attesters::is_registered(e, &attester)
    }

    pub fn get_registered_attesters(e: &Env) -> Vec<BytesN<32>> {
        attesters::get_all(e)
    }

    pub fn set_policy_id(e: &Env, caller: Address, policy_id: String) {
        policy::set(e, &caller, &policy_id);
    }

    pub fn get_policy_id(e: &Env, client: Address) -> String {
        policy::get(e, &client)
    }

    /// The digest an attester signs, bound to the host network so it is valid
    /// only on the chain that produced it.
    pub fn hash_statement(e: &Env, statement: Statement) -> BytesN<32> {
        validation::compute_hash(e, &statement)
    }

    /// `caller` should be `e.current_contract_address()`. It replaces
    /// `statement.target` before hashing, so an attestation only works for the
    /// contract presenting it; every other field is trusted exactly as passed.
    ///
    /// Expiry, replay, uuid or expiration disagreement, and an unregistered
    /// attester return a [`RegistryError`]. An invalid signature instead aborts
    /// the invocation with `Error(Crypto, InvalidInput)`, which is why no
    /// `InvalidSignature` variant exists. Neither outcome spends the uuid.
    pub fn validate_attestation(
        e: &Env,
        statement: Statement,
        attestation: Attestation,
        caller: Address,
    ) -> Result<(), RegistryError> {
        validation::validate(e, &statement, &attestation, &caller)
    }

    /// Swaps the bytecode in place: the address and all storage survive.
    /// `new_wasm_hash` must already be uploaded — see `stellar contract upload`.
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

    // Requires `stellar contract build --package predicate-registry` first: the
    // host validator only accepts the wasm32v1-none build.
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

    #[test]
    fn test_two_step_ownership_transfer() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let new_owner = Address::generate(&e);

        client.transfer_ownership(&owner, &new_owner);
        assert_eq!(client.owner(), owner); // still the old owner
        assert_eq!(client.pending_owner(), Some(new_owner.clone()));

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

    fn generate_ed25519_keypair(e: &Env) -> (ed25519_dalek::SigningKey, BytesN<32>) {
        use ed25519_dalek::SigningKey;
        use rand::rngs::OsRng;
        let sk = SigningKey::generate(&mut OsRng);
        let pk_bytes = sk.verifying_key().to_bytes();
        (sk, BytesN::from_array(e, &pk_bytes))
    }

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

        client.validate_attestation(&statement, &attestation, &client.address);
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

        client.validate_attestation(&statement, &attestation, &client.address);
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

    /// `target` is the caller, so `hash_statement` returns exactly what
    /// `validate_attestation` recomputes and the substitution is a no-op.
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

    /// Two instances on the same network hash identically; the registry address is
    /// not in the preimage, only the network id.
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

    /// An attestation signed on one chain cannot be presented on another.
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

    // These constants come from `scripts/golden-vector.js`, an implementation that
    // shares no code with this contract. Never regenerate them from `hash_statement`
    // — a vector derived from the code under test cannot detect the code changing.
    // Reordering the preimage or renaming a `Statement` field (`#[contracttype]`
    // uses field names as ScMap keys) alters the wire format, and every other test
    // here would still pass. The Go signer pins the same values.

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

    /// `target` is the address the test passes as `caller`, so the substitution in
    /// `validate_attestation` is a no-op and it hashes exactly this.
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

    #[test]
    fn test_golden_vector_digest() {
        let e = Env::default();
        e.mock_all_auths();
        e.ledger().set_network_id(unhex::<32>(GV_NETWORK_ID));
        let (_owner, client) = setup(&e);

        let digest = client.hash_statement(&golden_statement(&e));

        assert_eq!(to_hex(&digest.to_array()), GV_DIGEST);
    }

    /// The same vector through the verification path, so the ed25519 call is
    /// covered and not just the hashing.
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

        let caller = Address::from_str(&e, GV_TARGET);
        client.validate_attestation(&statement, &attestation, &caller);
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

        let attester = generate_attester_key(&e);
        client.register_attester(&owner, &attester);
        assert!(client.is_attester_registered(&attester));

        let wasm_hash = e.deployer().upload_contract_wasm(registry_wasm::WASM);
        client.upgrade(&owner, &wasm_hash);

        assert_eq!(client.owner(), owner);
        assert!(client.is_attester_registered(&attester));
    }

    /// A bad signature aborts with a host error, never a `RegistryError`.
    #[test]
    #[should_panic(expected = "Error(Crypto, InvalidInput)")]
    fn test_validate_invalid_signature() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        let (sk_a, pub_key_a) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key_a);

        // B is registered too, so only the signature can be what fails.
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
        let signature = sign_hash(&e, &sk_a, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key_b, // wrong attester for this signature
            signature,
        };

        client.validate_attestation(&statement, &attestation, &client.address);
    }

    /// The abort commits nothing, so the uuid survives for a corrected retry.
    /// `try_validate_attestation` observes it without unwinding.
    #[test]
    fn test_invalid_signature_aborts_and_leaves_uuid_unspent() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);

        let (sk, pub_key) = generate_ed25519_keypair(&e);
        let (other_sk, _other_pk) = generate_ed25519_keypair(&e);
        client.register_attester(&owner, &pub_key);

        let statement = Statement {
            uuid: soroban_sdk::String::from_str(&e, "uuid-retry-after-bad-sig"),
            msg_sender: Address::generate(&e),
            target: client.address.clone(),
            msg_value: 0,
            encoded_sig_and_args: soroban_sdk::Bytes::from_slice(&e, &[0u8; 32]),
            policy: soroban_sdk::String::from_str(&e, "x-test"),
            expiration: e.ledger().timestamp() + 600,
        };
        let hash = client.hash_statement(&statement);

        // Signed by a key the registry does not know: verification fails.
        let forged = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key.clone(),
            signature: sign_hash(&e, &other_sk, &hash),
        };
        let outcome = client.try_validate_attestation(&statement, &forged, &client.address);
        // Err at the outer level is the invocation failing. The inner Err being an
        // InvokeError rather than a RegistryError is the mismatch itself: there is
        // no contract error code here for a caller to branch on.
        assert_eq!(outcome, Err(Err(soroban_sdk::InvokeError::Abort)));

        // The failed attempt committed nothing, so the same uuid is still spendable.
        let genuine = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature: sign_hash(&e, &sk, &hash),
        };
        client.validate_attestation(&statement, &genuine, &client.address);
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
