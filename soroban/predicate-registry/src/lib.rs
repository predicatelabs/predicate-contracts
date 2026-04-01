#![no_std]

mod attesters;
mod policy;
mod types;
mod validation;

use soroban_sdk::{contract, contractimpl, Address, BytesN, Env, Symbol, Vec};

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

    /// Register a new attester. Only the contract owner may call this.
    pub fn register_attester(
        e: &Env,
        owner: Address,
        attester: BytesN<32>,
    ) -> Result<(), RegistryError> {
        require_owner(e, &owner)?;
        attesters::register(e, &attester)
    }

    /// Deregister an attester using swap-and-pop. Only the contract owner may call this.
    pub fn deregister_attester(
        e: &Env,
        owner: Address,
        attester: BytesN<32>,
    ) -> Result<(), RegistryError> {
        require_owner(e, &owner)?;
        attesters::deregister(e, &attester)
    }

    /// Check whether an attester is currently registered.
    pub fn is_attester_registered(e: &Env, attester: BytesN<32>) -> bool {
        attesters::is_registered(e, &attester)
    }

    /// Return all registered attesters.
    pub fn get_registered_attesters(e: &Env) -> Vec<BytesN<32>> {
        attesters::get_all(e)
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

#[cfg(test)]
mod test {
    extern crate std;

    use soroban_sdk::{testutils::Address as _, Address, BytesN, Env};

    use super::*;

    fn setup(e: &Env) -> (Address, PredicateRegistryContractClient) {
        let owner = Address::generate(e);
        let address = e.register(PredicateRegistryContract, (owner.clone(),));
        let client = PredicateRegistryContractClient::new(e, &address);
        (owner, client)
    }

    fn generate_attester_key(e: &Env) -> BytesN<32> {
        BytesN::from_array(e, &[1u8; 32])
    }

    fn generate_attester_key_2(e: &Env) -> BytesN<32> {
        BytesN::from_array(e, &[2u8; 32])
    }

    #[test]
    fn test_register_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let attester = generate_attester_key(&e);

        client.register_attester(&owner, &attester);

        assert!(client.is_attester_registered(&attester));
        let attesters = client.get_registered_attesters();
        assert_eq!(attesters.len(), 1);
        assert_eq!(attesters.get(0).unwrap(), attester);
    }

    #[test]
    fn test_deregister_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let attester = generate_attester_key(&e);

        client.register_attester(&owner, &attester);
        client.deregister_attester(&owner, &attester);

        assert!(!client.is_attester_registered(&attester));
        assert_eq!(client.get_registered_attesters().len(), 0);
    }

    #[test]
    fn test_deregister_swap_and_pop() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let a1 = generate_attester_key(&e);
        let a2 = generate_attester_key_2(&e);

        client.register_attester(&owner, &a1);
        client.register_attester(&owner, &a2);
        client.deregister_attester(&owner, &a1);

        assert!(!client.is_attester_registered(&a1));
        assert!(client.is_attester_registered(&a2));
        let attesters = client.get_registered_attesters();
        assert_eq!(attesters.len(), 1);
        assert_eq!(attesters.get(0).unwrap(), a2);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #2)")]
    fn test_register_duplicate_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let attester = generate_attester_key(&e);

        client.register_attester(&owner, &attester);
        client.register_attester(&owner, &attester);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #3)")]
    fn test_deregister_unregistered_attester() {
        let e = Env::default();
        e.mock_all_auths();
        let (owner, client) = setup(&e);
        let attester = generate_attester_key(&e);

        client.deregister_attester(&owner, &attester);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #1)")]
    fn test_non_owner_cannot_register() {
        let e = Env::default();
        e.mock_all_auths();
        let (_owner, client) = setup(&e);
        let not_owner = Address::generate(&e);
        let attester = generate_attester_key(&e);

        client.register_attester(&not_owner, &attester);
    }
}
