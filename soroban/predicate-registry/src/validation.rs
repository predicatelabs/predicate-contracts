use soroban_sdk::xdr::ToXdr;
use soroban_sdk::{symbol_short, Address, Bytes, BytesN, Env};

use crate::types::{Attestation, RegistryError, Statement};

/// Compute SHA-256 hash of a statement for attester signing.
///
/// The preimage is the deterministic XDR serialization of the host network ID
/// followed by the statement. The network ID is read from the ledger rather than
/// taken as a parameter, so a caller cannot choose the chain it is validated
/// against — this mirrors `block.chainid` in the EVM registry's
/// `hashStatementWithExpiry`.
///
/// There is no separate version tag. XDR is self-describing and length-prefixed,
/// so layouts cannot be confused for one another: this preimage opens with
/// `ScVal::Bytes`, where the previous one (a network passphrase) opened with
/// `ScVal::String`, and a statement is an `ScVal::Map` that no appended field
/// could impersonate. Changing the layout is therefore already a hard break, and
/// a tag would only restate that.
///
/// The registry's own address is deliberately *not* in the preimage, matching
/// EVM and Solana. Replay across registry instances is already constrained by
/// the caller binding below (see `validate`): it would need one integrating
/// contract wired to two registries running this same preimage layout. Adding
/// the address would instead require every attester to know which registry it is
/// signing for, and only one registry per network is deployed. If that ever
/// changes, append `e.current_contract_address()` here.
pub fn compute_hash(e: &Env, statement: &Statement) -> BytesN<32> {
    let mut payload = Bytes::new(e);

    // Domain separator, read from the host — not caller-supplied.
    payload.append(&e.ledger().network_id().to_xdr(e));
    // Statement fields in deterministic order
    payload.append(&statement.clone().to_xdr(e));

    e.crypto().sha256(&payload).to_bytes()
}

/// Longest window, in seconds, for which the registry will honour an attestation.
///
/// The attester decides each attestation's expiration, so without a ceiling a
/// single mis-issued one stays usable indefinitely — the realistic failure is not
/// an attacker but a units bug off-chain (milliseconds where seconds were meant
/// puts the expiration ~55,000 years out) or an operator typo. Capping the window
/// bounds that to a day rather than forever, and costs nothing in normal
/// operation: the Predicate API issues one-hour attestations by default, so this
/// leaves 24x headroom.
///
/// Consequence worth knowing before raising or lowering it: the API's TTL is
/// per-project configurable, and a project configured above this ceiling has its
/// attestations rejected on-chain. Keep that validation off-chain too, so the
/// mismatch surfaces when the project is configured rather than when a user
/// transacts. Changing this value requires a contract upgrade.
pub const MAX_ATTESTATION_LIFETIME: u64 = 24 * 60 * 60;

/// Validate an attestation against a statement.
///
/// Performs the following checks:
/// 0. Caller authentication (mirrors EVM's implicit msg.sender)
/// 1. Attestation not expired, and not valid for longer than
///    [`MAX_ATTESTATION_LIFETIME`]
/// 2. UUID not already spent (replay protection)
/// 3. UUID matches between statement and attestation
/// 4. Expiration matches between statement and attestation
/// 5. Attester is registered (cheap lookup before expensive crypto)
/// 6. Ed25519 signature verification using caller-bound hash (hashStatementSafe)
/// 7. Marks UUID as spent
/// 8. Emits validation event
pub fn validate(
    e: &Env,
    statement: &Statement,
    attestation: &Attestation,
    caller: &Address,
) -> Result<bool, RegistryError> {
    // 0. Authenticate the caller — mirrors EVM's implicit msg.sender guarantee.
    //    Without this, anyone could call validate_attestation with an arbitrary
    //    caller address and burn valid UUIDs.
    caller.require_auth();

    // 1. Check expiration. Both bounds are inclusive: an attestation is still
    //    valid on the exact second it expires, matching `block.timestamp <=
    //    expiration` in the EVM registry, and an expiration exactly
    //    MAX_ATTESTATION_LIFETIME away is accepted.
    let now = e.ledger().timestamp();
    if now > attestation.expiration {
        return Err(RegistryError::AttestationExpired);
    }
    // saturating_add so a near-u64::MAX timestamp cannot wrap into a low ceiling
    // that would wave the attestation through.
    if attestation.expiration > now.saturating_add(MAX_ATTESTATION_LIFETIME) {
        return Err(RegistryError::ExpirationTooFarInFuture);
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

    // 5. Check attester is registered (cheap lookup — do before expensive crypto)
    if !crate::attesters::is_registered(e, &attestation.attester) {
        return Err(RegistryError::AttesterNotRegistered);
    }

    // Maximum TTL the network allows for a ledger entry — used below to keep the
    // replay marker (and the attester's registration entries) alive for as long
    // as possible instead of a fixed short window.
    let max_ttl = e.storage().max_ttl();

    // 6. Ed25519 signature verification — use caller-bound hash (hashStatementSafe)
    // Replace statement.target with the actual caller to prevent cross-contract replay
    let safe_statement = Statement {
        target: caller.clone(),
        ..statement.clone()
    };
    let hash = compute_hash(e, &safe_statement);
    let hash_bytes: Bytes = Bytes::from_slice(e, &hash.to_array());
    // NOTE: ed25519_verify panics on invalid signature
    e.crypto()
        .ed25519_verify(&attestation.attester, &hash_bytes, &attestation.signature);

    // 7. Mark UUID as spent.
    //    Extend the replay marker to the maximum possible TTL. A fixed short TTL
    //    (~30 days) could be archived/evicted while a longer-lived attestation is
    //    still valid, which would re-open replay. Tying the marker to the network
    //    max keeps the guard alive for as long as the ledger allows.
    e.storage().persistent().set(&uuid_key, &true);
    e.storage()
        .persistent()
        .extend_ttl(&uuid_key, max_ttl, max_ttl);

    // Refresh the contract instance TTL on every successful validation so that
    // an actively-used registry (and its attester set, held in instance storage)
    // is never archived out from under callers.
    crate::attesters::refresh_ttl(e);

    // 8. Emit event (includes attester + caller for observability, mirroring EVM StatementValidated)
    #[allow(deprecated)]
    e.events().publish(
        (symbol_short!("validate"), symbol_short!("ok")),
        (
            statement.uuid.clone(),
            attestation.attester.clone(),
            caller.clone(),
        ),
    );

    Ok(true)
}
