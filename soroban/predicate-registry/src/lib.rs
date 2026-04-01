#![no_std]

mod attesters;
mod policy;
mod types;
mod validation;

use soroban_sdk::{contract, contractimpl, Address, BytesN, Env, String, Symbol, Vec};

pub use types::{Attestation, RegistryError, Statement};

// Storage keys
const OWNER: Symbol = soroban_sdk::symbol_short!("owner");

#[contract]
pub struct PredicateRegistryContract;

#[contractimpl]
impl PredicateRegistryContract {
    /// Initialize the registry with an owner address.
    pub fn __constructor(e: &Env, owner: Address) {
        e.storage().instance().set(&OWNER, &owner);
    }

    /// Return the contract owner.
    pub fn owner(e: &Env) -> Address {
        e.storage().instance().get(&OWNER).unwrap()
    }

    /// Transfer contract ownership. Only the current owner may call this.
    pub fn transfer_ownership(e: &Env, current_owner: Address, new_owner: Address) -> Result<(), RegistryError> {
        require_owner(e, &current_owner)?;
        e.storage().instance().set(&OWNER, &new_owner);
        Ok(())
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
    pub fn hash_statement(e: &Env, statement: Statement, network: String) -> BytesN<32> {
        validation::compute_hash(e, &statement, &network)
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
        network: String,
        caller: Address,
    ) -> Result<bool, RegistryError> {
        validation::validate(e, &statement, &attestation, &network, &caller)
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

    fn setup(e: &Env) -> (Address, PredicateRegistryContractClient) {
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
    fn test_transfer_ownership() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let new_owner = Address::generate(&e);

        client.transfer_ownership(&owner, &new_owner);
        assert_eq!(client.owner(), new_owner);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #1)")]
    fn test_non_owner_cannot_transfer() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);
        let attacker = Address::generate(&e);
        let new_owner = Address::generate(&e);

        client.transfer_ownership(&attacker, &new_owner);
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
        let network = soroban_sdk::String::from_str(&e, "Test SDF Network ; September 2015");

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

        let hash = client.hash_statement(&statement, &network);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        let result = client.validate_attestation(&statement, &attestation, &network, &client.address);
        assert!(result);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #4)")]
    fn test_validate_expired_attestation() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let network = soroban_sdk::String::from_str(&e, "testnet");

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

        let hash = client.hash_statement(&statement, &network);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: 0,
            attester: pub_key,
            signature,
        };

        client.validate_attestation(&statement, &attestation, &network, &client.address);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #5)")]
    fn test_validate_uuid_replay() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let network = soroban_sdk::String::from_str(&e, "testnet");

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

        let hash = client.hash_statement(&statement, &network);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        // First call succeeds
        client.validate_attestation(&statement, &attestation, &network, &client.address);
        // Second call should fail with UuidAlreadyUsed
        client.validate_attestation(&statement, &attestation, &network, &client.address);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #6)")]
    fn test_validate_uuid_mismatch() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let network = soroban_sdk::String::from_str(&e, "testnet");

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

        let hash = client.hash_statement(&statement, &network);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: soroban_sdk::String::from_str(&e, "uuid-B"), // mismatch
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        client.validate_attestation(&statement, &attestation, &network, &client.address);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #7)")]
    fn test_validate_expiration_mismatch() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let network = soroban_sdk::String::from_str(&e, "testnet");

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

        let hash = client.hash_statement(&statement, &network);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration + 100, // mismatch
            attester: pub_key,
            signature,
        };

        client.validate_attestation(&statement, &attestation, &network, &client.address);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #3)")]
    fn test_validate_unregistered_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);
        let network = soroban_sdk::String::from_str(&e, "testnet");

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

        let hash = client.hash_statement(&statement, &network);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        client.validate_attestation(&statement, &attestation, &network, &client.address);
    }

    #[test]
    #[should_panic] // ed25519_verify panics on bad signature
    fn test_validate_invalid_signature() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let network = soroban_sdk::String::from_str(&e, "testnet");

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

        let hash = client.hash_statement(&statement, &network);
        // Sign with key A but claim attester is key B
        let signature = sign_hash(&e, &sk_a, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key_b, // wrong attester for this signature
            signature,
        };

        client.validate_attestation(&statement, &attestation, &network, &client.address);
    }
}
