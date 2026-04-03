//! Attester registration and deregistration with O(1) swap-and-pop removal.
//!
//! The full attester list is stored in instance storage as a `Vec`. This design
//! assumes a small attester set (fewer than ~50 entries). For larger sets,
//! consider a persistent-storage-based approach with a separate length counter
//! to avoid deserializing the entire vector on every operation.

use soroban_sdk::{symbol_short, BytesN, Env, Vec};

use crate::types::{RegistryError, PERSISTENT_TTL_EXTEND, PERSISTENT_TTL_THRESHOLD};

// Storage keys
const ATTESTERS_KEY: soroban_sdk::Symbol = symbol_short!("atts");

fn att_reg_key(attester: &BytesN<32>) -> (soroban_sdk::Symbol, BytesN<32>) {
    (symbol_short!("att_reg"), attester.clone())
}

fn att_idx_key(attester: &BytesN<32>) -> (soroban_sdk::Symbol, BytesN<32>) {
    (symbol_short!("att_idx"), attester.clone())
}

pub fn register(e: &Env, attester: &BytesN<32>) -> Result<(), RegistryError> {
    // Check if already registered
    let registered: bool = e
        .storage()
        .persistent()
        .get(&att_reg_key(attester))
        .unwrap_or(false);
    if registered {
        return Err(RegistryError::AttesterAlreadyRegistered);
    }

    // Get or create the attesters vec
    let mut attesters: Vec<BytesN<32>> = e
        .storage()
        .instance()
        .get(&ATTESTERS_KEY)
        .unwrap_or(Vec::new(e));

    let index = attesters.len();
    attesters.push_back(attester.clone());

    // Store the vec
    e.storage().instance().set(&ATTESTERS_KEY, &attesters);
    // Mark as registered
    e.storage().persistent().set(&att_reg_key(attester), &true);
    e.storage().persistent().extend_ttl(
        &att_reg_key(attester),
        PERSISTENT_TTL_THRESHOLD,
        PERSISTENT_TTL_EXTEND,
    );
    // Store index
    e.storage().persistent().set(&att_idx_key(attester), &index);
    e.storage().persistent().extend_ttl(
        &att_idx_key(attester),
        PERSISTENT_TTL_THRESHOLD,
        PERSISTENT_TTL_EXTEND,
    );

    #[allow(deprecated)]
    e.events().publish(
        (symbol_short!("attester"), symbol_short!("reg")),
        attester.clone(),
    );

    Ok(())
}

pub fn deregister(e: &Env, attester: &BytesN<32>) -> Result<(), RegistryError> {
    // Check if registered
    let registered: bool = e
        .storage()
        .persistent()
        .get(&att_reg_key(attester))
        .unwrap_or(false);
    if !registered {
        return Err(RegistryError::AttesterNotRegistered);
    }

    let mut attesters: Vec<BytesN<32>> = e
        .storage()
        .instance()
        .get(&ATTESTERS_KEY)
        .unwrap_or(Vec::new(e));

    let index: u32 = e
        .storage()
        .persistent()
        .get(&att_idx_key(attester))
        .unwrap();

    let last_index = attesters.len() - 1;

    if index != last_index {
        // Swap with last element
        let last_attester = attesters.get(last_index).unwrap();
        attesters.set(index, last_attester.clone());
        // Update swapped element's index
        e.storage()
            .persistent()
            .set(&att_idx_key(&last_attester), &index);
    }

    // Pop the last element
    attesters.pop_back();

    // Store updated vec
    e.storage().instance().set(&ATTESTERS_KEY, &attesters);
    // Remove registration flag (remove entirely — is_registered uses unwrap_or(false))
    e.storage().persistent().remove(&att_reg_key(attester));
    // Remove index
    e.storage().persistent().remove(&att_idx_key(attester));

    #[allow(deprecated)]
    e.events().publish(
        (symbol_short!("attester"), symbol_short!("dereg")),
        attester.clone(),
    );

    Ok(())
}

pub fn is_registered(e: &Env, attester: &BytesN<32>) -> bool {
    e.storage()
        .persistent()
        .get(&att_reg_key(attester))
        .unwrap_or(false)
}

pub fn get_all(e: &Env) -> Vec<BytesN<32>> {
    e.storage()
        .instance()
        .get(&ATTESTERS_KEY)
        .unwrap_or(Vec::new(e))
}
