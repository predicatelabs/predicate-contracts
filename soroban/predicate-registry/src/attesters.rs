//! The set is a single `Vec` in instance storage, scanned linearly: it holds a
//! handful of keys at most, and instance storage needs no per-entry TTL upkeep.

use soroban_sdk::{symbol_short, BytesN, Env, Vec};

use crate::types::RegistryError;

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

/// Keeps an actively-used registry from being archived along with its attesters.
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
