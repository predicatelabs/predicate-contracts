use soroban_sdk::{symbol_short, Address, Env, String};

use crate::types::{PERSISTENT_TTL_EXTEND, PERSISTENT_TTL_THRESHOLD};

const POLICY_KEY: soroban_sdk::Symbol = symbol_short!("policy");

fn policy_storage_key(client: &Address) -> (soroban_sdk::Symbol, Address) {
    (POLICY_KEY, client.clone())
}

pub fn set(e: &Env, caller: &Address, policy_id: &String) {
    caller.require_auth();
    e.storage()
        .persistent()
        .set(&policy_storage_key(caller), policy_id);
    e.storage().persistent().extend_ttl(
        &policy_storage_key(caller),
        PERSISTENT_TTL_THRESHOLD,
        PERSISTENT_TTL_EXTEND,
    );
    #[allow(deprecated)]
    e.events().publish(
        (symbol_short!("policy"), symbol_short!("set")),
        (caller.clone(), policy_id.clone()),
    );
}

pub fn get(e: &Env, client: &Address) -> String {
    e.storage()
        .persistent()
        .get(&policy_storage_key(client))
        .unwrap_or(String::from_str(e, ""))
}
