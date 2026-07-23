//! Attester registration and deregistration.
//!
//! The attester set is held as a single `Vec` in instance storage. The registry
//! is expected to hold a very small set (typically one attester, at most a
//! handful), so membership checks and removals scan the vector linearly rather
//! than maintaining auxiliary per-attester flag/index entries. Because the set
//! lives in instance storage, its lifetime is tied to the contract instance and
//! needs no per-entry TTL bookkeeping.

use soroban_sdk::{symbol_short, BytesN, Env, Vec};

use crate::types::RegistryError;

// Storage key
const ATTESTERS_KEY: soroban_sdk::Symbol = symbol_short!("atts");

fn load(e: &Env) -> Vec<BytesN<32>> {
    e.storage()
        .instance()
        .get(&ATTESTERS_KEY)
        .unwrap_or(Vec::new(e))
}

fn store(e: &Env, attesters: &Vec<BytesN<32>>) {
    e.storage().instance().set(&ATTESTERS_KEY, attesters);
}

/// Extend the contract instance TTL to the network maximum. The attester set
/// lives in instance storage, so refreshing the instance on every successful
/// validation keeps an actively-used registry from being archived.
pub fn refresh_ttl(e: &Env) {
    let max_ttl = e.storage().max_ttl();
    e.storage().instance().extend_ttl(max_ttl, max_ttl);
}

pub fn register(e: &Env, attester: &BytesN<32>) -> Result<(), RegistryError> {
    let mut attesters = load(e);
    if attesters.contains(attester) {
        return Err(RegistryError::AttesterAlreadyRegistered);
    }

    attesters.push_back(attester.clone());
    store(e, &attesters);
    refresh_ttl(e);

    #[allow(deprecated)]
    e.events().publish(
        (symbol_short!("attester"), symbol_short!("reg")),
        attester.clone(),
    );

    Ok(())
}

pub fn deregister(e: &Env, attester: &BytesN<32>) -> Result<(), RegistryError> {
    let mut attesters = load(e);
    let index = attesters
        .first_index_of(attester)
        .ok_or(RegistryError::AttesterNotRegistered)?;

    // Swap-and-pop: move the last element into the vacated slot, then truncate.
    let last_index = attesters.len() - 1;
    if index != last_index {
        let last_attester = attesters.get(last_index).unwrap();
        attesters.set(index, last_attester);
    }
    attesters.pop_back();
    store(e, &attesters);
    refresh_ttl(e);

    #[allow(deprecated)]
    e.events().publish(
        (symbol_short!("attester"), symbol_short!("dereg")),
        attester.clone(),
    );

    Ok(())
}

pub fn is_registered(e: &Env, attester: &BytesN<32>) -> bool {
    load(e).contains(attester)
}

pub fn get_all(e: &Env) -> Vec<BytesN<32>> {
    load(e)
}
