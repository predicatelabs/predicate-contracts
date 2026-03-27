#![no_std]

// MuxedAddress, Symbol, Vec are used by OZ's #[contractimpl(contracttrait)] macro expansions
use soroban_sdk::{
    contract, contracterror, contractimpl, symbol_short, Address, Env, MuxedAddress, String,
    Symbol, Vec,
};
use stellar_access::access_control::{self as access_control, AccessControl};
use stellar_tokens::fungible::{
    blocklist::{BlockList, FungibleBlockList},
    burnable::FungibleBurnable,
    Base, FungibleToken,
};

#[contract]
pub struct TestStablecoinContract;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum TestStablecoinError {
    Unauthorized = 1,
}

#[contractimpl]
impl TestStablecoinContract {
    pub fn __constructor(
        e: &Env,
        name: String,
        symbol: String,
        admin: Address,
        manager: Address,
        blocker: Address,
        initial_supply: i128,
    ) {
        Base::set_metadata(e, 6, name, symbol);
        access_control::set_admin(e, &admin);
        access_control::grant_role_no_auth(e, &manager, &symbol_short!("manager"), &admin);
        access_control::grant_role_no_auth(e, &blocker, &symbol_short!("blocker"), &admin);
        Base::mint(e, &admin, initial_supply);
    }

    pub fn mint(e: &Env, to: Address, amount: i128) {
        access_control::enforce_admin_auth(e);
        Base::mint(e, &to, amount);
    }
}

#[contractimpl(contracttrait)]
impl FungibleToken for TestStablecoinContract {
    type ContractType = BlockList;
}

// Implement FungibleBlockList methods as contract functions.
// FungibleBlockList trait does not have #[contracttrait], so we implement
// the trait for access and expose the methods via a separate #[contractimpl].
impl FungibleBlockList for TestStablecoinContract {
    fn blocked(e: &Env, account: Address) -> bool {
        BlockList::blocked(e, &account)
    }

    fn block_user(e: &Env, user: Address, operator: Address) {
        access_control::ensure_role(e, &symbol_short!("blocker"), &operator);
        operator.require_auth();
        BlockList::block_user(e, &user)
    }

    fn unblock_user(e: &Env, user: Address, operator: Address) {
        access_control::ensure_role(e, &symbol_short!("blocker"), &operator);
        operator.require_auth();
        BlockList::unblock_user(e, &user)
    }
}

// Expose the FungibleBlockList methods as contract endpoints
#[contractimpl]
impl TestStablecoinContract {
    pub fn blocked(e: &Env, account: Address) -> bool {
        <Self as FungibleBlockList>::blocked(e, account)
    }

    pub fn block_user(e: &Env, user: Address, operator: Address) {
        <Self as FungibleBlockList>::block_user(e, user, operator)
    }

    pub fn unblock_user(e: &Env, user: Address, operator: Address) {
        <Self as FungibleBlockList>::unblock_user(e, user, operator)
    }
}

#[contractimpl(contracttrait)]
impl AccessControl for TestStablecoinContract {}

#[contractimpl(contracttrait)]
impl FungibleBurnable for TestStablecoinContract {
    fn burn(e: &Env, from: Address, amount: i128) {
        BlockList::burn(e, &from, amount);
    }

    fn burn_from(e: &Env, spender: Address, from: Address, amount: i128) {
        BlockList::burn_from(e, &spender, &from, amount);
    }
}

#[cfg(test)]
mod test {
    extern crate std;
    use soroban_sdk::{testutils::Address as _, Address, Env, String};

    use super::*;

    fn setup(e: &Env) -> (Address, Address, Address, TestStablecoinContractClient) {
        e.mock_all_auths();
        let admin = Address::generate(e);
        let manager = Address::generate(e);
        let blocker = Address::generate(e);
        let name = String::from_str(e, "Test USD");
        let symbol = String::from_str(e, "TUSD");
        let initial_supply = 1_000_000_000i128; // 1000 tokens with 6 decimals
        let address = e.register(
            TestStablecoinContract,
            (name, symbol, &admin, &manager, &blocker, initial_supply),
        );
        let client = TestStablecoinContractClient::new(e, &address);
        (admin, blocker, manager, client)
    }

    #[test]
    fn test_constructor() {
        let e = Env::default();
        let (admin, _blocker, _manager, client) = setup(&e);

        assert_eq!(client.decimals(), 6u32);
        assert_eq!(client.name(), String::from_str(&e, "Test USD"));
        assert_eq!(client.symbol(), String::from_str(&e, "TUSD"));
        assert_eq!(client.balance(&admin), 1_000_000_000i128);
    }

    #[test]
    fn test_mint() {
        let e = Env::default();
        let (_admin, _blocker, _manager, client) = setup(&e);
        let user = Address::generate(&e);

        client.mint(&user, &500_000i128);
        assert_eq!(client.balance(&user), 500_000i128);
    }

    #[test]
    fn test_transfer() {
        let e = Env::default();
        let (admin, _blocker, _manager, client) = setup(&e);
        let bob = Address::generate(&e);

        client.transfer(&admin, &bob, &100_000i128);
        assert_eq!(client.balance(&admin), 999_900_000i128);
        assert_eq!(client.balance(&bob), 100_000i128);
    }

    #[test]
    fn test_block_unblock() {
        let e = Env::default();
        let (admin, blocker, _manager, client) = setup(&e);
        let user = Address::generate(&e);

        // Block user
        client.block_user(&user, &blocker);
        assert!(client.blocked(&user));

        // Unblock user
        client.unblock_user(&user, &blocker);
        assert!(!client.blocked(&user));

        // Transfer works after unblock
        client.transfer(&admin, &user, &100i128);
        assert_eq!(client.balance(&user), 100i128);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #114)")]
    fn test_blocked_user_cannot_transfer() {
        let e = Env::default();
        let (admin, blocker, _manager, client) = setup(&e);
        let user = Address::generate(&e);

        client.transfer(&admin, &user, &1000i128);
        client.block_user(&user, &blocker);
        client.transfer(&user, &admin, &500i128);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #114)")]
    fn test_transfer_to_blocked_user() {
        let e = Env::default();
        let (admin, blocker, _manager, client) = setup(&e);
        let user = Address::generate(&e);

        client.block_user(&user, &blocker);
        client.transfer(&admin, &user, &500i128);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #114)")]
    fn test_blocked_user_cannot_approve() {
        let e = Env::default();
        let (_admin, blocker, _manager, client) = setup(&e);
        let user = Address::generate(&e);
        let spender = Address::generate(&e);

        client.block_user(&user, &blocker);
        client.approve(&user, &spender, &100i128, &1000u32);
    }

    #[test]
    fn test_approve_and_transfer_from() {
        let e = Env::default();
        let (admin, _blocker, _manager, client) = setup(&e);
        let spender = Address::generate(&e);
        let recipient = Address::generate(&e);

        client.approve(&admin, &spender, &500_000i128, &1000u32);
        assert_eq!(client.allowance(&admin, &spender), 500_000i128);

        client.transfer_from(&spender, &admin, &recipient, &200_000i128);
        assert_eq!(client.balance(&recipient), 200_000i128);
        assert_eq!(client.allowance(&admin, &spender), 300_000i128);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #114)")]
    fn test_transfer_from_blocked_user() {
        let e = Env::default();
        let (admin, blocker, _manager, client) = setup(&e);
        let spender = Address::generate(&e);
        let recipient = Address::generate(&e);

        client.approve(&admin, &spender, &500_000i128, &1000u32);
        client.block_user(&admin, &blocker);
        client.transfer_from(&spender, &admin, &recipient, &100i128);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #114)")]
    fn test_transfer_from_to_blocked_user() {
        let e = Env::default();
        let (admin, blocker, _manager, client) = setup(&e);
        let spender = Address::generate(&e);
        let recipient = Address::generate(&e);

        client.approve(&admin, &spender, &500_000i128, &1000u32);
        client.block_user(&recipient, &blocker);
        client.transfer_from(&spender, &admin, &recipient, &100i128);
    }

    #[test]
    fn test_burn() {
        let e = Env::default();
        let (admin, _blocker, _manager, client) = setup(&e);

        let before = client.balance(&admin);
        client.burn(&admin, &100_000i128);
        assert_eq!(client.balance(&admin), before - 100_000i128);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #114)")]
    fn test_blocked_user_cannot_burn() {
        let e = Env::default();
        let (admin, blocker, _manager, client) = setup(&e);

        client.block_user(&admin, &blocker);
        client.burn(&admin, &100i128);
    }

    #[test]
    #[should_panic(expected = "Error(Contract, #114)")]
    fn test_burn_from_blocked_user() {
        let e = Env::default();
        let (admin, blocker, _manager, client) = setup(&e);
        let spender = Address::generate(&e);

        client.approve(&admin, &spender, &500_000i128, &1000u32);
        client.block_user(&admin, &blocker);
        client.burn_from(&spender, &admin, &100i128);
    }

    #[test]
    #[should_panic]
    fn test_non_admin_cannot_mint() {
        let e = Env::default();
        // Set up contract without mocking auths globally
        let admin = Address::generate(&e);
        let manager = Address::generate(&e);
        let blocker = Address::generate(&e);
        let name = String::from_str(&e, "Test USD");
        let symbol = String::from_str(&e, "TUSD");
        let address = e.register(
            TestStablecoinContract,
            (name, symbol, &admin, &manager, &blocker, 1_000_000i128),
        );
        let client = TestStablecoinContractClient::new(&e, &address);
        let user = Address::generate(&e);

        // Call mint without any auth mocked — should fail
        client.mint(&user, &1000i128);
    }

    #[test]
    #[should_panic]
    fn test_non_blocker_cannot_block() {
        let e = Env::default();
        let admin = Address::generate(&e);
        let manager = Address::generate(&e);
        let blocker = Address::generate(&e);
        let name = String::from_str(&e, "Test USD");
        let symbol = String::from_str(&e, "TUSD");
        let address = e.register(
            TestStablecoinContract,
            (name, symbol, &admin, &manager, &blocker, 1_000_000i128),
        );
        let client = TestStablecoinContractClient::new(&e, &address);
        let user = Address::generate(&e);
        let not_blocker = Address::generate(&e);

        // Call block_user with a non-blocker operator — should fail
        client.block_user(&user, &not_blocker);
    }
}
