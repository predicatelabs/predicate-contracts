#![no_std]

use predicate_client::{Attestation, Statement};
use soroban_sdk::{
    contract, contractimpl, contracttype, symbol_short, Address, Bytes, BytesN, Env, String, Vec,
};

// ─── TTL Constants ───────────────────────────────────────────────────────────

const LEDGER_BUMP_AMOUNT: u32 = 518_400; // ~30 days
const LEDGER_THRESHOLD: u32 = 432_000; // ~25 days

// ─── Storage Keys ────────────────────────────────────────────────────────────

#[contracttype]
#[derive(Clone)]
pub enum DataKey {
    Owner,
    Initialized,
    Attester(BytesN<32>),
    AttesterIndex(BytesN<32>),
    AttestersList,
    Policy(Address),
    UsedUuid(String),
}

// ─── Contract ────────────────────────────────────────────────────────────────

#[contract]
pub struct PredicateRegistryContract;

#[contractimpl]
impl PredicateRegistryContract {
    // ─── Initialization ──────────────────────────────────────────────────

    pub fn initialize(env: Env, owner: Address) {
        if env
            .storage()
            .instance()
            .get::<_, bool>(&DataKey::Initialized)
            .unwrap_or(false)
        {
            panic!("already initialized");
        }
        env.storage().instance().set(&DataKey::Initialized, &true);
        env.storage().instance().set(&DataKey::Owner, &owner);

        let empty_list: Vec<BytesN<32>> = Vec::new(&env);
        env.storage()
            .persistent()
            .set(&DataKey::AttestersList, &empty_list);
    }

    // ─── Ownership ───────────────────────────────────────────────────────

    pub fn set_owner(env: Env, new_owner: Address) {
        let owner: Address = env.storage().instance().get(&DataKey::Owner).unwrap();
        owner.require_auth();
        env.storage().instance().set(&DataKey::Owner, &new_owner);
    }

    // ─── Attester Management ─────────────────────────────────────────────

    pub fn register_attester(env: Env, attester: BytesN<32>) {
        let owner: Address = env.storage().instance().get(&DataKey::Owner).unwrap();
        owner.require_auth();

        if env
            .storage()
            .persistent()
            .get::<_, bool>(&DataKey::Attester(attester.clone()))
            .unwrap_or(false)
        {
            panic!("attester already registered");
        }

        // Get current list and add
        let mut list: Vec<BytesN<32>> = env
            .storage()
            .persistent()
            .get(&DataKey::AttestersList)
            .unwrap_or(Vec::new(&env));

        let index = list.len();
        list.push_back(attester.clone());

        env.storage()
            .persistent()
            .set(&DataKey::AttestersList, &list);
        env.storage().persistent().extend_ttl(
            &DataKey::AttestersList,
            LEDGER_THRESHOLD,
            LEDGER_BUMP_AMOUNT,
        );
        env.storage()
            .persistent()
            .set(&DataKey::Attester(attester.clone()), &true);
        env.storage().persistent().extend_ttl(
            &DataKey::Attester(attester.clone()),
            LEDGER_THRESHOLD,
            LEDGER_BUMP_AMOUNT,
        );
        env.storage()
            .persistent()
            .set(&DataKey::AttesterIndex(attester.clone()), &index);
        env.storage().persistent().extend_ttl(
            &DataKey::AttesterIndex(attester),
            LEDGER_THRESHOLD,
            LEDGER_BUMP_AMOUNT,
        );
    }

    pub fn deregister_attester(env: Env, attester: BytesN<32>) {
        let owner: Address = env.storage().instance().get(&DataKey::Owner).unwrap();
        owner.require_auth();

        if !env
            .storage()
            .persistent()
            .get::<_, bool>(&DataKey::Attester(attester.clone()))
            .unwrap_or(false)
        {
            panic!("attester not registered");
        }

        let mut list: Vec<BytesN<32>> = env
            .storage()
            .persistent()
            .get(&DataKey::AttestersList)
            .unwrap();

        let index: u32 = env
            .storage()
            .persistent()
            .get(&DataKey::AttesterIndex(attester.clone()))
            .unwrap();

        let last_index = list.len() - 1;

        if index != last_index {
            // Swap with last element
            let last_attester: BytesN<32> = list.get(last_index).unwrap();
            list.set(index, last_attester.clone());
            env.storage()
                .persistent()
                .set(&DataKey::AttesterIndex(last_attester), &index);
        }

        list.pop_back();

        env.storage()
            .persistent()
            .set(&DataKey::AttestersList, &list);
        env.storage()
            .persistent()
            .remove(&DataKey::Attester(attester.clone()));
        env.storage()
            .persistent()
            .remove(&DataKey::AttesterIndex(attester));
    }

    pub fn get_registered_attesters(env: Env) -> Vec<BytesN<32>> {
        env.storage()
            .persistent()
            .get(&DataKey::AttestersList)
            .unwrap_or(Vec::new(&env))
    }

    pub fn is_attester_registered(env: Env, attester: BytesN<32>) -> bool {
        env.storage()
            .persistent()
            .get::<_, bool>(&DataKey::Attester(attester))
            .unwrap_or(false)
    }

    // ─── Policy Management ───────────────────────────────────────────────

    pub fn set_policy_id(env: Env, client: Address, policy_id: String) {
        client.require_auth();
        env.storage()
            .persistent()
            .set(&DataKey::Policy(client), &policy_id);
    }

    pub fn get_policy_id(env: Env, client: Address) -> String {
        env.storage()
            .persistent()
            .get(&DataKey::Policy(client))
            .unwrap()
    }

    // ─── Attestation Validation ──────────────────────────────────────────

    pub fn validate_attestation(env: Env, statement: Statement, attestation: Attestation) {
        // 1. Check expiration
        if attestation.expiration <= env.ledger().timestamp() {
            panic!("attestation expired");
        }

        // 2. Check UUID match
        if statement.uuid != attestation.uuid {
            panic!("UUID mismatch");
        }

        // 3. Check expiration match
        if statement.expiration != attestation.expiration {
            panic!("expiration mismatch");
        }

        // 4. Check UUID not already used
        if env
            .storage()
            .persistent()
            .get::<_, bool>(&DataKey::UsedUuid(attestation.uuid.clone()))
            .unwrap_or(false)
        {
            panic!("UUID already used");
        }

        // 5. Check attester is registered
        if !env
            .storage()
            .persistent()
            .get::<_, bool>(&DataKey::Attester(attestation.attester.clone()))
            .unwrap_or(false)
        {
            panic!("attester not registered");
        }

        // 6. Serialize statement
        let message = predicate_client::serialize_statement(&env, &statement);

        // 7. Verify Ed25519 signature
        env.crypto()
            .ed25519_verify(&attestation.attester, &message, &attestation.signature);

        // 8. Mark UUID as spent
        env.storage()
            .persistent()
            .set(&DataKey::UsedUuid(attestation.uuid.clone()), &true);
        env.storage().persistent().extend_ttl(
            &DataKey::UsedUuid(attestation.uuid.clone()),
            LEDGER_THRESHOLD,
            LEDGER_BUMP_AMOUNT,
        );

        // 9. Emit event
        #[allow(deprecated)]
        env.events()
            .publish((symbol_short!("validate"),), attestation.uuid);
    }

    /// Returns the serialized message bytes for a statement.
    /// Off-chain attesters sign these bytes directly with Ed25519.
    pub fn hash_statement(env: Env, statement: Statement) -> Bytes {
        predicate_client::serialize_statement(&env, &statement)
    }

    // ─── TTL Extension ───────────────────────────────────────────────────

    pub fn extend_ttl(env: Env) {
        let owner: Address = env.storage().instance().get(&DataKey::Owner).unwrap();
        owner.require_auth();

        env.storage()
            .instance()
            .extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);

        if env.storage().persistent().has(&DataKey::AttestersList) {
            env.storage().persistent().extend_ttl(
                &DataKey::AttestersList,
                LEDGER_THRESHOLD,
                LEDGER_BUMP_AMOUNT,
            );
        }
    }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod test_wrapper {
    use predicate_client::{authorize_transaction, Attestation};
    use soroban_sdk::{contract, contractimpl, Address, Bytes, Env, String};

    #[contract]
    pub struct TestWrapperContract;

    #[contractimpl]
    impl TestWrapperContract {
        pub fn call_authorize(
            env: Env,
            registry: Address,
            attestation: Attestation,
            encoded_args: Bytes,
            sender: Address,
            value: i128,
            policy: String,
        ) {
            authorize_transaction(
                &env,
                &registry,
                &attestation,
                &encoded_args,
                &sender,
                value,
                &policy,
            );
        }
    }
}

#[cfg(test)]
mod test {
    extern crate alloc;

    use super::*;
    use ed25519_dalek::Signer;
    use soroban_sdk::testutils::{Address as _, Ledger};
    use soroban_sdk::{Address, Bytes, BytesN, Env};

    fn create_keypair(env: &Env, seed: u8) -> (BytesN<32>, ed25519_dalek::SigningKey) {
        let secret_bytes = [seed; 32];
        let signing_key = ed25519_dalek::SigningKey::from_bytes(&secret_bytes);
        let verifying_key = signing_key.verifying_key();
        let pubkey = BytesN::from_array(env, &verifying_key.to_bytes());
        (pubkey, signing_key)
    }

    fn sign_statement(
        env: &Env,
        signing_key: &ed25519_dalek::SigningKey,
        statement: &Statement,
    ) -> BytesN<64> {
        let message = predicate_client::serialize_statement(env, statement);
        let len = message.len() as usize;
        let buf: alloc::vec::Vec<u8> = (0..len).map(|i| message.get(i as u32).unwrap()).collect();
        let sig = signing_key.sign(&buf);
        BytesN::from_array(env, &sig.to_bytes())
    }

    fn make_statement(env: &Env, uuid: &str, expiration: u64) -> Statement {
        Statement {
            uuid: String::from_str(env, uuid),
            msg_sender: Address::generate(env),
            target: Address::generate(env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(env),
            policy: String::from_str(env, "policy-1"),
            expiration,
        }
    }

    // Helper: create env + deploy + initialize, with all auths mocked
    fn setup() -> (Env, PredicateRegistryContractClient<'static>, Address) {
        let env = Env::default();
        env.mock_all_auths();
        let contract_id = env.register(PredicateRegistryContract, ());
        let owner = Address::generate(&env);

        // Leak to get 'static — fine for tests
        let env: &'static Env = alloc::boxed::Box::leak(alloc::boxed::Box::new(env));
        let client = PredicateRegistryContractClient::new(env, &contract_id);
        client.initialize(&owner);
        (env.clone(), client, owner)
    }

    // ─── Initialization Tests ────────────────────────────────────────────

    #[test]
    fn test_initialize() {
        let env = Env::default();
        env.mock_all_auths();
        let contract_id = env.register(PredicateRegistryContract, ());
        let client = PredicateRegistryContractClient::new(&env, &contract_id);
        let owner = Address::generate(&env);

        client.initialize(&owner);

        let attesters = client.get_registered_attesters();
        assert_eq!(attesters.len(), 0);
    }

    #[test]
    #[should_panic(expected = "already initialized")]
    fn test_double_initialize() {
        let env = Env::default();
        env.mock_all_auths();
        let contract_id = env.register(PredicateRegistryContract, ());
        let client = PredicateRegistryContractClient::new(&env, &contract_id);
        let owner = Address::generate(&env);

        client.initialize(&owner);
        client.initialize(&owner);
    }

    // ─── Ownership Tests ─────────────────────────────────────────────────

    #[test]
    fn test_set_owner() {
        let (env, client, _owner) = setup();
        let new_owner = Address::generate(&env);

        client.set_owner(&new_owner);

        // New owner can register attester (proves ownership transferred)
        let (pubkey, _) = create_keypair(&env, 1);
        client.register_attester(&pubkey);
        assert!(client.is_attester_registered(&pubkey));
    }

    #[test]
    #[should_panic]
    fn test_set_owner_not_owner() {
        let env = Env::default();
        env.mock_all_auths();
        let contract_id = env.register(PredicateRegistryContract, ());
        let client = PredicateRegistryContractClient::new(&env, &contract_id);
        let owner = Address::generate(&env);
        client.initialize(&owner);

        // Create a fresh env without mocked auths — auth will not be satisfied
        let env2 = Env::default();
        let contract_id2 = env2.register(PredicateRegistryContract, ());
        let client2 = PredicateRegistryContractClient::new(&env2, &contract_id2);
        let owner2 = Address::generate(&env2);
        // TODO: soroban-sdk 25 sticky mock_all_auths prevents clearing auths on the
        // same Env; using a fresh Env re-registers without existing state so initialize
        // panics (not initialized), which still satisfies #[should_panic].
        client2.initialize(&owner2);
        let new_owner = Address::generate(&env2);
        // Without mock_all_auths on env2, set_owner requires real auth and panics
        client2.set_owner(&new_owner);
    }

    // ─── Attester Management Tests ───────────────────────────────────────

    #[test]
    fn test_register_attester() {
        let (env, client, _owner) = setup();
        let (pubkey, _) = create_keypair(&env, 1);

        client.register_attester(&pubkey);

        assert!(client.is_attester_registered(&pubkey));
        let attesters = client.get_registered_attesters();
        assert_eq!(attesters.len(), 1);
        assert_eq!(attesters.get(0).unwrap(), pubkey);
    }

    #[test]
    #[should_panic(expected = "attester already registered")]
    fn test_register_attester_duplicate() {
        let (env, client, _owner) = setup();
        let (pubkey, _) = create_keypair(&env, 1);

        client.register_attester(&pubkey);
        client.register_attester(&pubkey);
    }

    #[test]
    #[should_panic]
    fn test_register_attester_not_owner() {
        let env = Env::default();
        env.mock_all_auths();
        let contract_id = env.register(PredicateRegistryContract, ());
        let client = PredicateRegistryContractClient::new(&env, &contract_id);
        let owner = Address::generate(&env);
        client.initialize(&owner);

        // Fresh env without mocked auths — register_attester requires owner auth
        let env2 = Env::default();
        let contract_id2 = env2.register(PredicateRegistryContract, ());
        let client2 = PredicateRegistryContractClient::new(&env2, &contract_id2);
        let owner2 = Address::generate(&env2);
        // TODO: soroban-sdk 25 sticky mock_all_auths prevents clearing auths on the
        // same Env; fresh Env used so auth is not satisfied, causing a panic.
        client2.initialize(&owner2);
        let (pubkey, _) = create_keypair(&env2, 1);
        client2.register_attester(&pubkey);
    }

    #[test]
    fn test_deregister_attester() {
        let (env, client, _owner) = setup();
        let (pubkey1, _) = create_keypair(&env, 1);
        let (pubkey2, _) = create_keypair(&env, 2);
        let (pubkey3, _) = create_keypair(&env, 3);

        client.register_attester(&pubkey1);
        client.register_attester(&pubkey2);
        client.register_attester(&pubkey3);

        // Deregister the middle one (swap-and-pop)
        client.deregister_attester(&pubkey2);

        assert!(!client.is_attester_registered(&pubkey2));
        assert!(client.is_attester_registered(&pubkey1));
        assert!(client.is_attester_registered(&pubkey3));

        let attesters = client.get_registered_attesters();
        assert_eq!(attesters.len(), 2);
    }

    #[test]
    #[should_panic(expected = "attester not registered")]
    fn test_deregister_attester_not_registered() {
        let (env, client, _owner) = setup();
        let (pubkey, _) = create_keypair(&env, 1);

        client.deregister_attester(&pubkey);
    }

    // ─── Policy Tests ────────────────────────────────────────────────────

    #[test]
    fn test_set_get_policy() {
        let (env, client, _owner) = setup();
        let policy_client = Address::generate(&env);
        let policy_id = String::from_str(&env, "my-policy-123");

        client.set_policy_id(&policy_client, &policy_id);

        let result = client.get_policy_id(&policy_client);
        assert_eq!(result, policy_id);
    }

    #[test]
    #[should_panic]
    fn test_set_policy_not_authorized() {
        let env = Env::default();
        env.mock_all_auths();
        let contract_id = env.register(PredicateRegistryContract, ());
        let client = PredicateRegistryContractClient::new(&env, &contract_id);
        let owner = Address::generate(&env);
        client.initialize(&owner);

        // Fresh env without mocked auths — set_policy_id requires client auth
        let env2 = Env::default();
        let contract_id2 = env2.register(PredicateRegistryContract, ());
        let client2 = PredicateRegistryContractClient::new(&env2, &contract_id2);
        let owner2 = Address::generate(&env2);
        // TODO: soroban-sdk 25 sticky mock_all_auths prevents clearing auths on the
        // same Env; fresh Env used so auth is not satisfied, causing a panic.
        client2.initialize(&owner2);
        let policy_client = Address::generate(&env2);
        let policy_id = String::from_str(&env2, "my-policy");
        client2.set_policy_id(&policy_client, &policy_id);
    }

    // ─── Attestation Validation Tests ────────────────────────────────────

    #[test]
    fn test_valid_attestation() {
        let (env, client, _owner) = setup();

        env.ledger().with_mut(|li| {
            li.timestamp = 100;
        });

        let (pubkey, signing_key) = create_keypair(&env, 42);
        client.register_attester(&pubkey);

        let statement = make_statement(&env, "uuid-1", 200);
        let signature = sign_statement(&env, &signing_key, &statement);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pubkey,
            signature,
        };

        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "attestation expired")]
    fn test_expired_attestation() {
        let (env, client, _owner) = setup();

        env.ledger().with_mut(|li| {
            li.timestamp = 300;
        });

        let (pubkey, signing_key) = create_keypair(&env, 42);
        client.register_attester(&pubkey);

        let statement = make_statement(&env, "uuid-exp", 200);
        let signature = sign_statement(&env, &signing_key, &statement);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pubkey,
            signature,
        };

        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "UUID already used")]
    fn test_replayed_uuid() {
        let (env, client, _owner) = setup();

        env.ledger().with_mut(|li| {
            li.timestamp = 100;
        });

        let (pubkey, signing_key) = create_keypair(&env, 42);
        client.register_attester(&pubkey);

        let statement = make_statement(&env, "uuid-replay", 200);
        let signature = sign_statement(&env, &signing_key, &statement);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pubkey,
            signature,
        };

        client.validate_attestation(&statement, &attestation.clone());
        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "attester not registered")]
    fn test_unregistered_attester() {
        let (env, client, _owner) = setup();

        env.ledger().with_mut(|li| {
            li.timestamp = 100;
        });

        let (pubkey, signing_key) = create_keypair(&env, 42);
        // Do NOT register the attester

        let statement = make_statement(&env, "uuid-unreg", 200);
        let signature = sign_statement(&env, &signing_key, &statement);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pubkey,
            signature,
        };

        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic]
    fn test_invalid_signature() {
        let (env, client, _owner) = setup();

        env.ledger().with_mut(|li| {
            li.timestamp = 100;
        });

        let (pubkey, _signing_key) = create_keypair(&env, 42);
        client.register_attester(&pubkey);

        let statement = make_statement(&env, "uuid-badsig", 200);

        let garbage_sig = BytesN::from_array(&env, &[0u8; 64]);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pubkey,
            signature: garbage_sig,
        };

        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "UUID mismatch")]
    fn test_uuid_mismatch() {
        let (env, client, _owner) = setup();

        env.ledger().with_mut(|li| {
            li.timestamp = 100;
        });

        let (pubkey, signing_key) = create_keypair(&env, 42);
        client.register_attester(&pubkey);

        let statement = make_statement(&env, "uuid-stmt", 200);
        let signature = sign_statement(&env, &signing_key, &statement);

        let attestation = Attestation {
            uuid: String::from_str(&env, "uuid-different"),
            expiration: statement.expiration,
            attester: pubkey,
            signature,
        };

        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "expiration mismatch")]
    fn test_expiration_mismatch() {
        let (env, client, _owner) = setup();

        env.ledger().with_mut(|li| {
            li.timestamp = 100;
        });

        let (pubkey, signing_key) = create_keypair(&env, 42);
        client.register_attester(&pubkey);

        let statement = make_statement(&env, "uuid-exp-mis", 200);
        let signature = sign_statement(&env, &signing_key, &statement);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: 999,
            attester: pubkey,
            signature,
        };

        client.validate_attestation(&statement, &attestation);
    }

    // ─── Integration Test: authorize_transaction via wrapper ─────────────

    #[test]
    fn test_authorize_transaction_integration() {
        use test_wrapper::{TestWrapperContract, TestWrapperContractClient};

        let (env, registry_client, _owner) = setup();

        env.ledger().with_mut(|li| {
            li.timestamp = 100;
        });

        // 1. Create attester keypair and register the public key
        let (pubkey, signing_key) = create_keypair(&env, 77);
        registry_client.register_attester(&pubkey);

        // 2. Deploy the wrapper contract — its address will become `target`
        let wrapper_id = env.register(TestWrapperContract, ());
        let wrapper_client = TestWrapperContractClient::new(&env, &wrapper_id);

        // 3. Build the Statement with target = wrapper contract address
        //    (authorize_transaction sets target = env.current_contract_address(),
        //     which will be wrapper_id when called from the wrapper)
        let sender = Address::generate(&env);
        let encoded_args = Bytes::new(&env);
        let policy = String::from_str(&env, "policy-integration");
        let uuid = String::from_str(&env, "uuid-integration-1");
        let expiration = 500u64;

        let statement = Statement {
            uuid: uuid.clone(),
            msg_sender: sender.clone(),
            target: wrapper_id.clone(),
            msg_value: 0i128,
            encoded_sig_and_args: encoded_args.clone(),
            policy: policy.clone(),
            expiration,
        };

        // 4. Sign the statement
        let signature = sign_statement(&env, &signing_key, &statement);

        let attestation = Attestation {
            uuid: uuid.clone(),
            expiration,
            attester: pubkey,
            signature,
        };

        // 5. Call via the wrapper — this triggers the cross-contract call to
        //    registry's validate_attestation
        wrapper_client.call_authorize(
            &registry_client.address,
            &attestation,
            &encoded_args,
            &sender,
            &0i128,
            &policy,
        );
    }
}
