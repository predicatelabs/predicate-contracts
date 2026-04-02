#![no_std]

/// Re-export registry types for downstream convenience.
pub use predicate_registry::{Attestation, RegistryError, Statement};

use soroban_sdk::{vec, Address, Bytes, Env, IntoVal, String, Symbol, Val, Vec};

/// Build a Statement and validate it against the Predicate Registry.
///
/// This is the Soroban equivalent of the EVM PredicateClient._authorizeTransaction() pattern.
///
/// The `uuid` and `expiration` fields are copied from the attestation into the
/// constructed statement, mirroring the EVM pattern where these values originate
/// from the attester's signed payload.
///
/// # Arguments
/// * `e` - Soroban environment
/// * `registry` - Address of the deployed PredicateRegistry contract
/// * `attestation` - The signed attestation from an authorized attester
/// * `encoded_sig_and_args` - Encoded function call data (variable-length)
/// * `msg_sender` - The original caller
/// * `msg_value` - Value sent with the transaction (token amount, equivalent to EVM msg.value)
/// * `target` - The contract being called — callers should pass `e.current_contract_address()`
///   so that the registry's hashStatementSafe logic can bind the attestation to this contract
/// * `policy` - The policy ID for this contract
/// * `network` - Network passphrase for domain separation
pub fn authorize_transaction(
    e: &Env,
    registry: &Address,
    attestation: &Attestation,
    encoded_sig_and_args: &Bytes,
    msg_sender: &Address,
    msg_value: i128,
    target: &Address,
    policy: &String,
    network: &String,
) -> bool {
    let statement = Statement {
        uuid: attestation.uuid.clone(),
        msg_sender: msg_sender.clone(),
        target: target.clone(),
        msg_value,
        encoded_sig_and_args: encoded_sig_and_args.clone(),
        policy: policy.clone(),
        expiration: attestation.expiration,
    };

    let args: Vec<Val> = vec![
        e,
        statement.into_val(e),
        attestation.clone().into_val(e),
        network.clone().into_val(e),
        target.clone().into_val(e),
    ];

    e.invoke_contract::<bool>(registry, &Symbol::new(e, "validate_attestation"), args)
}

#[cfg(test)]
mod test {
    extern crate std;

    use super::*;
    use predicate_registry::PredicateRegistryContract;
    use soroban_sdk::{testutils::Address as _, Address, BytesN, Env};

    fn setup_registry(e: &Env) -> (Address, Address) {
        let owner = Address::generate(e);
        let registry_addr = e.register(PredicateRegistryContract, (owner.clone(),));
        (owner, registry_addr)
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
    fn test_authorize_transaction_end_to_end() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, registry_addr) = setup_registry(&e);
        let network = String::from_str(&e, "Test SDF Network ; September 2015");

        // Register an attester via the registry client
        let registry_client =
            predicate_registry::PredicateRegistryContractClient::new(&e, &registry_addr);
        let (sk, pub_key) = generate_ed25519_keypair(&e);
        registry_client.register_attester(&owner, &pub_key);

        // Simulate a downstream contract calling authorize_transaction
        let msg_sender = Address::generate(&e);
        let target = Address::generate(&e);
        let policy = String::from_str(&e, "x-test-policy");
        let encoded = Bytes::from_slice(&e, &[0xBBu8; 16]);
        let msg_value: i128 = 1000;

        // Build the statement the same way authorize_transaction will,
        // then hash+sign it so the registry can verify.
        let statement = Statement {
            uuid: String::from_str(&e, "uuid-client-test"),
            msg_sender: msg_sender.clone(),
            target: target.clone(),
            msg_value,
            encoded_sig_and_args: encoded.clone(),
            policy: policy.clone(),
            expiration: e.ledger().timestamp() + 600,
        };

        let hash = registry_client.hash_statement(&statement, &network);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: statement.uuid.clone(),
            expiration: statement.expiration,
            attester: pub_key,
            signature,
        };

        let result = authorize_transaction(
            &e,
            &registry_addr,
            &attestation,
            &encoded,
            &msg_sender,
            msg_value,
            &target,
            &policy,
            &network,
        );
        assert!(result);
    }
}
