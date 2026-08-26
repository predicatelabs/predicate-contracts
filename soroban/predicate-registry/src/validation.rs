use soroban_sdk::xdr::ToXdr;
use soroban_sdk::{symbol_short, Address, Bytes, BytesN, Env};

use crate::types::{Attestation, RegistryError, Statement};

/// SHA-256 over the XDR of the host network id followed by the statement.
///
/// The network id comes from the ledger, never a parameter, so a caller cannot
/// choose the chain its signature is checked against.
pub fn compute_hash(e: &Env, statement: &Statement) -> BytesN<32> {
    let mut payload = Bytes::new(e);

    payload.append(&e.ledger().network_id().to_xdr(e));
    payload.append(&statement.clone().to_xdr(e));

    e.crypto().sha256(&payload).to_bytes()
}

/// Verify that a registered attester signed `statement`, then spend its uuid.
/// An invalid signature traps instead of returning `Err`; see the note below.
pub fn validate(
    e: &Env,
    statement: &Statement,
    attestation: &Attestation,
    caller: &Address,
) -> Result<(), RegistryError> {
    // Without this, anyone could pass another contract's address and spend uuids
    // against it.
    caller.require_auth();

    if e.ledger().timestamp() > attestation.expiration {
        return Err(RegistryError::AttestationExpired);
    }

    let uuid_key = (symbol_short!("uuid"), statement.uuid.clone());
    let already_used: bool = e.storage().persistent().get(&uuid_key).unwrap_or(false);
    if already_used {
        return Err(RegistryError::UuidAlreadyUsed);
    }

    if statement.uuid != attestation.uuid {
        return Err(RegistryError::UuidMismatch);
    }

    if statement.expiration != attestation.expiration {
        return Err(RegistryError::ExpirationMismatch);
    }

    if !crate::attesters::is_registered(e, &attestation.attester) {
        return Err(RegistryError::AttesterNotRegistered);
    }

    let max_ttl = e.storage().max_ttl();

    // Binding the digest to the authenticated caller rather than the statement's
    // own target is what stops one contract's attestation working on another.
    let safe_statement = Statement {
        target: caller.clone(),
        ..statement.clone()
    };
    let hash = compute_hash(e, &safe_statement);
    let hash_bytes: Bytes = Bytes::from_slice(e, &hash.to_array());
    // Traps on failure rather than returning: soroban-sdk 23.5.3 exposes no
    // fallible ed25519 API, so callers see an aborted invocation, not an Err.
    e.crypto()
        .ed25519_verify(&attestation.attester, &hash_bytes, &attestation.signature);

    // Max TTL: a marker archived while its attestation is still valid re-opens
    // replay.
    e.storage().persistent().set(&uuid_key, &true);
    e.storage()
        .persistent()
        .extend_ttl(&uuid_key, max_ttl, max_ttl);

    crate::attesters::refresh_ttl(e);

    #[allow(deprecated)]
    e.events().publish(
        (symbol_short!("validate"), symbol_short!("ok")),
        (
            statement.uuid.clone(),
            attestation.attester.clone(),
            caller.clone(),
        ),
    );

    Ok(())
}
