#![no_std]

use soroban_sdk::{contracttype, Address, Bytes, BytesN, Env, IntoVal, String, Symbol, Val, Vec};

pub use soroban_sdk::xdr::ToXdr;

// ─── Types ────────────────────────────────────────────────────────────────────

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Statement {
    pub uuid: String,
    pub msg_sender: Address,
    pub target: Address,
    pub msg_value: i128,
    pub encoded_sig_and_args: Bytes,
    pub policy: String,
    pub expiration: u64,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Attestation {
    pub uuid: String,
    pub expiration: u64,
    pub attester: BytesN<32>,  // Ed25519 public key
    pub signature: BytesN<64>, // Ed25519 signature
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Serializes a Statement into deterministic bytes for Ed25519 signing.
///
/// Wire format: `network_id (32 bytes) || statement XDR (variable length)`
pub fn serialize_statement(env: &Env, statement: &Statement) -> Bytes {
    let network_id = env.ledger().network_id();
    let mut message = Bytes::from_slice(env, &network_id.to_array());
    let statement_xdr = statement.clone().to_xdr(env);
    message.append(&statement_xdr);
    message
}

/// Constructs a Statement from the attestation and call context, then invokes
/// the registry contract's `validate_attestation` entry point via a
/// cross-contract call.
///
/// This is called from within a protected contract function. The registry is
/// responsible for verifying the Ed25519 signature over the serialized
/// Statement and enforcing policy / expiration rules.
pub fn authorize_transaction(
    env: &Env,
    registry_address: &Address,
    attestation: &Attestation,
    encoded_sig_and_args: &Bytes,
    msg_sender: &Address,
    msg_value: i128,
    policy: &String,
) {
    let statement = Statement {
        uuid: attestation.uuid.clone(),
        msg_sender: msg_sender.clone(),
        target: env.current_contract_address(),
        msg_value,
        encoded_sig_and_args: encoded_sig_and_args.clone(),
        policy: policy.clone(),
        expiration: attestation.expiration,
    };

    let args: Vec<Val> = soroban_sdk::vec![
        env,
        statement.into_val(env),
        attestation.clone().into_val(env),
    ];

    env.invoke_contract::<()>(
        registry_address,
        &Symbol::new(env, "validate_attestation"),
        args,
    );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod test {
    use super::*;
    use soroban_sdk::testutils::Address as _;
    use soroban_sdk::{Address, Bytes, Env};

    #[test]
    fn test_statement_construction() {
        let env = Env::default();
        let statement = Statement {
            uuid: String::from_str(&env, "test-uuid"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 1000u64,
        };
        assert_eq!(statement.uuid, String::from_str(&env, "test-uuid"));
        assert_eq!(statement.expiration, 1000u64);
    }

    #[test]
    fn test_serialize_statement_length() {
        let env = Env::default();
        let statement = Statement {
            uuid: String::from_str(&env, "test-uuid"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 1000u64,
        };

        let serialized = serialize_statement(&env, &statement);

        // Must be at least 32 bytes (network_id) + some XDR bytes
        assert!(serialized.len() >= 32);

        // The first 32 bytes are the network_id
        let network_id = env.ledger().network_id();
        for i in 0..32u32 {
            assert_eq!(
                serialized.get(i).unwrap(),
                network_id.to_array()[i as usize]
            );
        }
    }

    #[test]
    fn test_serialize_statement_deterministic() {
        let env = Env::default();
        let sender = Address::generate(&env);
        let target = Address::generate(&env);

        let statement1 = Statement {
            uuid: String::from_str(&env, "uuid-abc"),
            msg_sender: sender.clone(),
            target: target.clone(),
            msg_value: 42i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "p"),
            expiration: 9999u64,
        };

        let statement2 = Statement {
            uuid: String::from_str(&env, "uuid-abc"),
            msg_sender: sender,
            target,
            msg_value: 42i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "p"),
            expiration: 9999u64,
        };

        assert_eq!(
            serialize_statement(&env, &statement1),
            serialize_statement(&env, &statement2)
        );
    }

    #[test]
    fn test_attestation_construction() {
        let env = Env::default();
        let key_bytes = [1u8; 32];
        let sig_bytes = [2u8; 64];

        let attestation = Attestation {
            uuid: String::from_str(&env, "attest-uuid"),
            expiration: 5000u64,
            attester: BytesN::from_array(&env, &key_bytes),
            signature: BytesN::from_array(&env, &sig_bytes),
        };

        assert_eq!(attestation.expiration, 5000u64);
        assert_eq!(attestation.attester, BytesN::from_array(&env, &key_bytes));
    }
}
