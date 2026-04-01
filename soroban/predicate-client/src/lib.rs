#![no_std]

/// Re-export registry types for downstream convenience.
pub use predicate_registry::{Attestation, RegistryError, Statement};

use soroban_sdk::{vec, Address, BytesN, Env, IntoVal, String, Symbol, Val, Vec};

/// Build a Statement and validate it against the Predicate Registry.
///
/// This is the Soroban equivalent of the EVM PredicateClient._authorizeTransaction() pattern.
///
/// # Arguments
/// * `e` - Soroban environment
/// * `registry` - Address of the deployed PredicateRegistry contract
/// * `attestation` - The signed attestation from an authorized attester
/// * `encoded_sig_and_args` - Hash of the function call being authorized
/// * `msg_sender` - The original caller
/// * `target` - The contract being called (typically `e.current_contract_address()`)
/// * `policy` - The policy ID for this contract
/// * `network` - Network passphrase for domain separation
pub fn authorize_transaction(
    e: &Env,
    registry: &Address,
    attestation: &Attestation,
    encoded_sig_and_args: &BytesN<32>,
    msg_sender: &Address,
    target: &Address,
    policy: &String,
    network: &String,
) -> bool {
    let statement = Statement {
        uuid: attestation.uuid.clone(),
        msg_sender: msg_sender.clone(),
        target: target.clone(),
        encoded_sig_and_args: encoded_sig_and_args.clone(),
        policy: policy.clone(),
        expiration: attestation.expiration,
    };

    let args: Vec<Val> = vec![
        e,
        statement.into_val(e),
        attestation.clone().into_val(e),
        network.clone().into_val(e),
    ];

    e.invoke_contract::<bool>(registry, &Symbol::new(e, "validate_attestation"), args)
}
