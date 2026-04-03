#![no_std]

use predicate_client::Attestation;
use soroban_sdk::{
    contract, contracterror, contractimpl, symbol_short, Address, Bytes, Env, String, Symbol,
};

// Storage keys
const ADMIN: Symbol = symbol_short!("admin");
const REGISTRY: Symbol = symbol_short!("registry");
const POLICY: Symbol = symbol_short!("policy");
const NETWORK: Symbol = symbol_short!("network");

/// Storage key for token balances: (BALANCE, address) -> i128
const BALANCE: Symbol = symbol_short!("balance");

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum TokenError {
    InsufficientBalance = 1,
    InvalidAmount = 2,
}

/// A minimal token contract that requires Predicate attestation for transfers.
///
/// This demonstrates how to integrate `predicate-client` into a Soroban contract.
/// Every transfer must be accompanied by a valid attestation from a registered attester,
/// proving the transaction satisfies the configured compliance policy.
#[contract]
pub struct CompliantTokenContract;

#[contractimpl]
impl CompliantTokenContract {
    /// Deploy the token with a Predicate Registry binding.
    ///
    /// # Arguments
    /// * `admin` - Token admin who can mint
    /// * `registry` - Address of the deployed PredicateRegistry contract
    /// * `policy_id` - Policy identifier (e.g. "x-a1b2c3d4e5f6g7h8")
    /// * `network` - Stellar network passphrase (e.g. "Test SDF Network ; September 2015")
    pub fn __constructor(
        e: &Env,
        admin: Address,
        registry: Address,
        policy_id: String,
        network: String,
    ) {
        e.storage().instance().set(&ADMIN, &admin);
        e.storage().instance().set(&REGISTRY, &registry);
        e.storage().instance().set(&POLICY, &policy_id);
        e.storage().instance().set(&NETWORK, &network);
    }

    /// Register this contract's policy with the Predicate Registry.
    /// Call this once after deployment. The admin must authorize.
    pub fn register_policy(e: &Env) {
        let admin: Address = e.storage().instance().get(&ADMIN).unwrap();
        admin.require_auth();

        let registry: Address = e.storage().instance().get(&REGISTRY).unwrap();
        let policy_id: String = e.storage().instance().get(&POLICY).unwrap();

        let args: soroban_sdk::Vec<soroban_sdk::Val> = soroban_sdk::vec![
            e,
            soroban_sdk::IntoVal::into_val(&e.current_contract_address(), e),
            soroban_sdk::IntoVal::into_val(&policy_id, e),
        ];
        e.invoke_contract::<()>(&registry, &Symbol::new(e, "set_policy_id"), args);
    }

    /// Mint tokens to an address. Admin only, no attestation required.
    pub fn mint(e: &Env, to: Address, amount: i128) {
        let admin: Address = e.storage().instance().get(&ADMIN).unwrap();
        admin.require_auth();

        let key = (BALANCE, to.clone());
        let current: i128 = e.storage().persistent().get(&key).unwrap_or(0);
        e.storage().persistent().set(&key, &(current + amount));
    }

    /// Transfer tokens. Requires a valid Predicate attestation.
    ///
    /// This is the key function: before moving tokens, it calls the Predicate
    /// Registry via `predicate_client::authorize_transaction()` to verify that
    /// the transfer is compliant with the configured policy.
    pub fn transfer(
        e: &Env,
        from: Address,
        to: Address,
        amount: i128,
        attestation: Attestation,
    ) -> Result<(), TokenError> {
        from.require_auth();

        if amount <= 0 {
            return Err(TokenError::InvalidAmount);
        }

        // Check balance
        let from_key = (BALANCE, from.clone());
        let balance: i128 = e.storage().persistent().get(&from_key).unwrap_or(0);
        if balance < amount {
            return Err(TokenError::InsufficientBalance);
        }

        // --- Predicate compliance check ---
        let registry: Address = e.storage().instance().get(&REGISTRY).unwrap();
        let policy: String = e.storage().instance().get(&POLICY).unwrap();
        let network: String = e.storage().instance().get(&NETWORK).unwrap();

        // Encode the transfer call data for the attestation
        let encoded_call = Bytes::from_slice(
            e,
            &e.crypto()
                .sha256(&soroban_sdk::Bytes::from_slice(
                    e,
                    b"transfer(address,address,i128)",
                ))
                .to_array(),
        );

        predicate_client::authorize_transaction(
            e,
            &registry,
            &attestation,
            &encoded_call,
            &from,
            amount,
            &e.current_contract_address(),
            &policy,
            &network,
        );
        // --- End compliance check ---

        // Execute transfer
        let to_key = (BALANCE, to.clone());
        let to_balance: i128 = e.storage().persistent().get(&to_key).unwrap_or(0);
        e.storage().persistent().set(&from_key, &(balance - amount));
        e.storage()
            .persistent()
            .set(&to_key, &(to_balance + amount));

        Ok(())
    }

    /// Query token balance.
    pub fn balance(e: &Env, account: Address) -> i128 {
        let key = (BALANCE, account);
        e.storage().persistent().get(&key).unwrap_or(0)
    }

    /// Query the registry address.
    pub fn registry(e: &Env) -> Address {
        e.storage().instance().get(&REGISTRY).unwrap()
    }

    /// Query the policy ID.
    pub fn policy_id(e: &Env) -> String {
        e.storage().instance().get(&POLICY).unwrap()
    }
}

#[cfg(test)]
mod test {
    extern crate std;

    use super::*;
    use predicate_registry::{PredicateRegistryContract, Statement};
    use soroban_sdk::{testutils::Address as _, BytesN, Env};

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

    /// Full end-to-end: deploy registry, deploy token, mint, transfer with attestation
    #[test]
    fn test_compliant_transfer() {
        let e = Env::default();
        e.mock_all_auths();

        let network = String::from_str(&e, "Test SDF Network ; September 2015");
        let policy_id = String::from_str(&e, "x-example-policy");

        // 1. Deploy the Predicate Registry
        let registry_owner = Address::generate(&e);
        let registry_addr = e.register(PredicateRegistryContract, (registry_owner.clone(),));
        let registry_client =
            predicate_registry::PredicateRegistryContractClient::new(&e, &registry_addr);

        // 2. Register an attester
        let (attester_sk, attester_pk) = generate_ed25519_keypair(&e);
        registry_client.register_attester(&registry_owner, &attester_pk);

        // 3. Deploy the compliant token
        let admin = Address::generate(&e);
        let token_addr = e.register(
            CompliantTokenContract,
            (
                admin.clone(),
                registry_addr.clone(),
                policy_id.clone(),
                network.clone(),
            ),
        );
        let token = CompliantTokenContractClient::new(&e, &token_addr);

        // 4. Register policy with the registry
        token.register_policy();

        // 5. Mint tokens
        let alice = Address::generate(&e);
        let bob = Address::generate(&e);
        token.mint(&alice, &1000);
        assert_eq!(token.balance(&alice), 1000);

        // 6. Build attestation for the transfer
        let transfer_amount: i128 = 250;
        let encoded_call = Bytes::from_slice(
            &e,
            &e.crypto()
                .sha256(&Bytes::from_slice(&e, b"transfer(address,address,i128)"))
                .to_array(),
        );

        let statement = Statement {
            uuid: String::from_str(&e, "transfer-001"),
            msg_sender: alice.clone(),
            target: token_addr.clone(),
            msg_value: transfer_amount,
            encoded_sig_and_args: encoded_call,
            policy: policy_id.clone(),
            expiration: e.ledger().timestamp() + 600,
        };

        // Hash and sign (this is what the Predicate API does off-chain)
        let hash = registry_client.hash_statement(&statement, &network);
        let signature = sign_hash(&e, &attester_sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: attester_pk,
            signature,
        };

        // 7. Transfer with attestation — should succeed
        token.transfer(&alice, &bob, &transfer_amount, &attestation);

        assert_eq!(token.balance(&alice), 750);
        assert_eq!(token.balance(&bob), 250);
    }

    #[test]
    #[should_panic(expected = "HostError: Error(Contract")]
    fn test_transfer_without_valid_attestation() {
        let e = Env::default();
        e.mock_all_auths();

        let network = String::from_str(&e, "Test SDF Network ; September 2015");
        let policy_id = String::from_str(&e, "x-example-policy");

        // Deploy registry and register a real attester
        let registry_owner = Address::generate(&e);
        let registry_addr = e.register(PredicateRegistryContract, (registry_owner.clone(),));
        let registry_client =
            predicate_registry::PredicateRegistryContractClient::new(&e, &registry_addr);

        let (_attester_sk, attester_pk) = generate_ed25519_keypair(&e);
        registry_client.register_attester(&registry_owner, &attester_pk);

        let admin = Address::generate(&e);
        let token_addr = e.register(
            CompliantTokenContract,
            (
                admin.clone(),
                registry_addr.clone(),
                policy_id.clone(),
                network.clone(),
            ),
        );
        let token = CompliantTokenContractClient::new(&e, &token_addr);

        // Register policy so the only failure is the bad attestation
        token.register_policy();

        let alice = Address::generate(&e);
        let bob = Address::generate(&e);
        token.mint(&alice, &1000);

        // Fake attestation with garbage signature — should fail verification
        let attestation = Attestation {
            uuid: String::from_str(&e, "fake-uuid"),
            expiration: e.ledger().timestamp() + 600,
            attester: BytesN::from_array(&e, &[0xFFu8; 32]),
            signature: BytesN::from_array(&e, &[0x00u8; 64]),
        };

        token.transfer(&alice, &bob, &100, &attestation);
    }
}
