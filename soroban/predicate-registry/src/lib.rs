#![no_std]

mod attesters;
mod policy;
mod types;
mod validation;

use soroban_sdk::{contract, contractimpl, Address, Env, Symbol};

pub use types::{Attestation, RegistryError, Statement};

// Storage keys
const OWNER: Symbol = soroban_sdk::symbol_short!("owner");

#[contract]
pub struct PredicateRegistryContract;

#[contractimpl]
impl PredicateRegistryContract {
    /// Initialize the registry with an owner address.
    pub fn __constructor(e: &Env, owner: Address) {
        e.storage().instance().set(&OWNER, &owner);
    }

    /// Return the contract owner.
    pub fn owner(e: &Env) -> Address {
        e.storage().instance().get(&OWNER).unwrap()
    }
}

/// Internal helper: require that `caller` is the stored owner.
pub(crate) fn require_owner(e: &Env, caller: &Address) -> Result<(), RegistryError> {
    let owner: Address = e
        .storage()
        .instance()
        .get(&OWNER)
        .ok_or(RegistryError::NotInitialized)?;
    if *caller != owner {
        return Err(RegistryError::Unauthorized);
    }
    caller.require_auth();
    Ok(())
}
