use soroban_sdk::{symbol_short, Address, Env, String};

const POLICY_KEY: soroban_sdk::Symbol = symbol_short!("policy");

fn policy_storage_key(client: &Address) -> (soroban_sdk::Symbol, Address) {
    (POLICY_KEY, client.clone())
}

pub fn set(e: &Env, caller: &Address, policy_id: &String) {
    caller.require_auth();
    e.storage()
        .persistent()
        .set(&policy_storage_key(caller), policy_id);
    // Extend to the network maximum: a fixed short TTL that is never refreshed
    // could archive a client's policy binding while it is still in use.
    let max_ttl = e.storage().max_ttl();
    e.storage()
        .persistent()
        .extend_ttl(&policy_storage_key(caller), max_ttl, max_ttl);
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
