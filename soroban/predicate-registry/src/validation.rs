use soroban_sdk::{symbol_short, Bytes, BytesN, Env, String};
use soroban_sdk::xdr::ToXdr;

use crate::types::{Attestation, RegistryError, Statement};

/// Compute SHA-256 hash of a statement + network passphrase for attester signing.
///
/// Uses deterministic XDR serialization of the statement and network passphrase.
pub fn compute_hash(e: &Env, statement: &Statement, network: &String) -> BytesN<32> {
    let mut payload = Bytes::new(e);

    // Domain separator: network passphrase
    payload.append(&network.clone().to_xdr(e));
    // Statement fields in deterministic order
    payload.append(&statement.clone().to_xdr(e));

    e.crypto().sha256(&payload).to_bytes()
}

/// Validate an attestation against a statement.
///
/// Performs the following checks:
/// 1. Attestation not expired
/// 2. UUID not already spent (replay protection)
/// 3. UUID matches between statement and attestation
/// 4. Expiration matches between statement and attestation
/// 5. Ed25519 signature verification (panics on failure)
/// 6. Attester is registered
/// 7. Marks UUID as spent
/// 8. Emits validation event
pub fn validate(
    e: &Env,
    statement: &Statement,
    attestation: &Attestation,
    network: &String,
) -> Result<bool, RegistryError> {
    // 1. Check expiration
    if e.ledger().timestamp() > attestation.expiration {
        return Err(RegistryError::AttestationExpired);
    }

    // 2. Check UUID not already spent
    let uuid_key = (symbol_short!("uuid"), statement.uuid.clone());
    let already_used: bool = e.storage().persistent().get(&uuid_key).unwrap_or(false);
    if already_used {
        return Err(RegistryError::UuidAlreadyUsed);
    }

    // 3. UUID match
    if statement.uuid != attestation.uuid {
        return Err(RegistryError::UuidMismatch);
    }

    // 4. Expiration match
    if statement.expiration != attestation.expiration {
        return Err(RegistryError::ExpirationMismatch);
    }

    // 5. Ed25519 signature verification
    let hash = compute_hash(e, statement, network);
    let hash_bytes: Bytes = Bytes::from_slice(e, &hash.to_array());
    // NOTE: ed25519_verify panics on invalid signature
    e.crypto()
        .ed25519_verify(&attestation.attester, &hash_bytes, &attestation.signature);

    // 6. Check attester is registered
    if !crate::attesters::is_registered(e, &attestation.attester) {
        return Err(RegistryError::AttesterNotRegistered);
    }

    // 7. Mark UUID as spent
    e.storage().persistent().set(&uuid_key, &true);

    // 8. Emit event
    e.events().publish(
        (symbol_short!("validate"), symbol_short!("ok")),
        statement.uuid.clone(),
    );

    Ok(true)
}
