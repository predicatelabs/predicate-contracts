#![no_std]

use soroban_sdk::{
    contracterror, contracttype, vec, Address, Bytes, BytesN, Env, IntoVal, String, Symbol, Val,
    Vec,
};

// --- Types (mirrored from predicate-registry to avoid linking the contract impl) ---

/// Describes a transaction to be authorized.
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

/// Ed25519-signed authorization from an attester.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Attestation {
    pub uuid: String,
    pub expiration: u64,
    pub attester: BytesN<32>,
    pub signature: BytesN<64>,
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum RegistryError {
    Unauthorized = 1,
    AttesterAlreadyRegistered = 2,
    AttesterNotRegistered = 3,
    AttestationExpired = 4,
    UuidAlreadyUsed = 5,
    UuidMismatch = 6,
    ExpirationMismatch = 7,
    InvalidSignature = 8,
    NotInitialized = 9,
    AlreadyInitialized = 10,
    ExpirationTooFarInFuture = 11,
}

// --- Client helper ---

/// Build a Statement and validate it against the Predicate Registry.
///
/// This is the Soroban equivalent of the EVM PredicateClient._authorizeTransaction() pattern.
///
/// The `uuid` and `expiration` fields are copied from the attestation into the
/// constructed statement, mirroring the EVM pattern where these values originate
/// from the attester's signed payload.
///
/// Returns `()` on success. On failure the registry returns an `Err`, and
/// `invoke_contract` propagates it as a trap carrying the registry's exact typed
/// error (e.g. `Error(Contract, #4)` for an expired attestation). The registry
/// never returns `Ok(false)`, so there is no boolean outcome for the caller to
/// branch on — a returning call means the transaction was authorized.
///
/// # Every argument must come from the live call
///
/// This helper exists to put the registry's trust boundary somewhere hard to get
/// wrong. The registry establishes only `target` (from the authenticated caller)
/// and the network (from the ledger) on its own; every other statement field is
/// taken on trust. So a returning call means "an attester signed the statement
/// built from these arguments" — which authorizes the action actually executing
/// only if the arguments describe it.
///
/// Derive each one from the function you are protecting, never from a parameter an
/// end user can choose. Forwarding user-supplied values here validates one action
/// while executing another, with no signature forgery involved.
///
/// # Arguments
/// * `e` - Soroban environment
/// * `registry` - Address of the deployed PredicateRegistry contract
/// * `attestation` - The signed attestation from an authorized attester
/// * `encoded_sig_and_args` - Encoding of the *concrete* call: selector plus every
///   argument that matters for compliance. Omitting an argument leaves it free to
///   change between attestation and execution — see `encode_transfer_call` in
///   `example-compliant-token`, and the tampered-recipient/amount tests that pin it
/// * `msg_sender` - The live sender, already `require_auth()`ed by the caller
/// * `msg_value` - The live value (token amount, equivalent to EVM msg.value)
/// * `target` - The contract being called — callers should pass `e.current_contract_address()`
///   so that the registry's hashStatementSafe logic can bind the attestation to this contract
/// * `policy` - This contract's configured policy, read from its own storage
///
/// Domain separation (the network) is derived by the registry from the ledger, so
/// there is nothing for the integrator to configure or get wrong here.
// The argument list mirrors the Statement fields on purpose. Collapsing it into a
// params struct would make it natural to build one value and reuse it across
// calls, which is exactly what the section above rules out.
#[allow(clippy::too_many_arguments)]
pub fn authorize_transaction(
    e: &Env,
    registry: &Address,
    attestation: &Attestation,
    encoded_sig_and_args: &Bytes,
    msg_sender: &Address,
    msg_value: i128,
    target: &Address,
    policy: &String,
) {
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
        target.clone().into_val(e),
    ];

    // The registry returns `Ok(true)` or traps with a typed `RegistryError`; the
    // `true` carries no information, so we discard it and rely on trap propagation
    // to surface the real error to the caller.
    let _: bool = e.invoke_contract(registry, &Symbol::new(e, "validate_attestation"), args);
}

#[cfg(test)]
mod test {
    extern crate std;

    use super::*;
    use predicate_registry::PredicateRegistryContract;
    use soroban_sdk::{testutils::Address as _, Address, Env};

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

        let registry_client =
            predicate_registry::PredicateRegistryContractClient::new(&e, &registry_addr);
        let (sk, pub_key) = generate_ed25519_keypair(&e);
        registry_client.register_attester(&owner, &pub_key);

        let msg_sender = Address::generate(&e);
        let target = Address::generate(&e);
        let policy = String::from_str(&e, "x-test-policy");
        let encoded = Bytes::from_slice(&e, &[0xBBu8; 16]);
        let msg_value: i128 = 1000;

        // Build statement matching what authorize_transaction will build
        let statement = predicate_registry::Statement {
            uuid: String::from_str(&e, "uuid-client-test"),
            msg_sender: msg_sender.clone(),
            target: target.clone(),
            msg_value,
            encoded_sig_and_args: encoded.clone(),
            policy: policy.clone(),
            expiration: e.ledger().timestamp() + 600,
        };

        let hash = registry_client.hash_statement(&statement);
        let signature = sign_hash(&e, &sk, &hash);

        let attestation = Attestation {
            uuid: String::from_str(&e, "uuid-client-test"),
            expiration: e.ledger().timestamp() + 600,
            attester: pub_key,
            signature,
        };

        // A returning call means the transaction was authorized; a failed
        // validation would trap and fail the test.
        authorize_transaction(
            &e,
            &registry_addr,
            &attestation,
            &encoded,
            &msg_sender,
            msg_value,
            &target,
            &policy,
        );
    }
}
