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
