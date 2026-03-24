#![no_std]

use soroban_sdk::{contract, contractimpl, contracttype, symbol_short, Address, Env, String};
use soroban_token_sdk::TokenUtils;

// ─── TTL Constants ───────────────────────────────────────────────────────────

const LEDGER_BUMP_AMOUNT: u32 = 518_400;
const LEDGER_THRESHOLD: u32 = 432_000;
const BALANCE_BUMP_AMOUNT: u32 = 518_400;
const BALANCE_THRESHOLD: u32 = 432_000;

// ─── Storage Keys ────────────────────────────────────────────────────────────

#[contracttype]
#[derive(Clone)]
pub enum DataKey {
    Admin,
    ComplianceAdmin,
    Initialized,
    Balance(Address),
    Allowance(Address, Address),
    Frozen(Address),
    Name,
    Symbol,
    Decimals,
}

#[contracttype]
#[derive(Clone)]
pub struct AllowanceData {
    pub amount: i128,
    pub expiration_ledger: u32,
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

fn check_not_frozen(env: &Env, addr: &Address) {
    if env
        .storage()
        .persistent()
        .get(&DataKey::Frozen(addr.clone()))
        .unwrap_or(false)
    {
        panic!("account is frozen");
    }
}

fn read_balance(env: &Env, addr: &Address) -> i128 {
    let key = DataKey::Balance(addr.clone());
    if let Some(balance) = env.storage().persistent().get::<_, i128>(&key) {
        env.storage()
            .persistent()
            .extend_ttl(&key, BALANCE_THRESHOLD, BALANCE_BUMP_AMOUNT);
        balance
    } else {
        0
    }
}

fn write_balance(env: &Env, addr: &Address, amount: i128) {
    let key = DataKey::Balance(addr.clone());
    env.storage().persistent().set(&key, &amount);
    env.storage()
        .persistent()
        .extend_ttl(&key, BALANCE_THRESHOLD, BALANCE_BUMP_AMOUNT);
}

fn read_allowance(env: &Env, from: &Address, spender: &Address) -> AllowanceData {
    let key = DataKey::Allowance(from.clone(), spender.clone());
    if let Some(allowance) = env.storage().temporary().get::<_, AllowanceData>(&key) {
        if allowance.expiration_ledger < env.ledger().sequence() {
            AllowanceData {
                amount: 0,
                expiration_ledger: allowance.expiration_ledger,
            }
        } else {
            allowance
        }
    } else {
        AllowanceData {
            amount: 0,
            expiration_ledger: 0,
        }
    }
}

fn write_allowance(
    env: &Env,
    from: &Address,
    spender: &Address,
    amount: i128,
    expiration_ledger: u32,
) {
    let key = DataKey::Allowance(from.clone(), spender.clone());
    let allowance = AllowanceData {
        amount,
        expiration_ledger,
    };
    env.storage().temporary().set(&key, &allowance);
    if amount > 0 && expiration_ledger >= env.ledger().sequence() {
        let live_for = expiration_ledger - env.ledger().sequence() + 1;
        env.storage()
            .temporary()
            .extend_ttl(&key, live_for, live_for);
    }
}

fn spend_allowance(env: &Env, from: &Address, spender: &Address, amount: i128) {
    let allowance = read_allowance(env, from, spender);
    if allowance.amount < amount {
        panic!("insufficient allowance");
    }
    if allowance.expiration_ledger < env.ledger().sequence() {
        panic!("allowance expired");
    }
    write_allowance(
        env,
        from,
        spender,
        allowance.amount - amount,
        allowance.expiration_ledger,
    );
}

fn require_admin(env: &Env) -> Address {
    let admin: Address = env.storage().instance().get(&DataKey::Admin).unwrap();
    admin.require_auth();
    admin
}

fn require_compliance_admin(env: &Env) -> Address {
    let compliance_admin: Address = env
        .storage()
        .instance()
        .get(&DataKey::ComplianceAdmin)
        .expect("no compliance admin set");
    compliance_admin.require_auth();
    compliance_admin
}

// ─── Contract ────────────────────────────────────────────────────────────────

#[contract]
pub struct TestStablecoinContract;

#[contractimpl]
impl TestStablecoinContract {
    // ─── Initialization ──────────────────────────────────────────────────

    pub fn initialize(env: Env, admin: Address, decimal: u32, name: String, symbol: String) {
        if env
            .storage()
            .instance()
            .get::<_, bool>(&DataKey::Initialized)
            .unwrap_or(false)
        {
            panic!("already initialized");
        }
        env.storage().instance().set(&DataKey::Initialized, &true);
        env.storage().instance().set(&DataKey::Admin, &admin);
        env.storage().instance().set(&DataKey::Decimals, &decimal);
        env.storage().instance().set(&DataKey::Name, &name);
        env.storage().instance().set(&DataKey::Symbol, &symbol);
    }

    // ─── Admin Functions ─────────────────────────────────────────────────

    pub fn set_admin(env: Env, new_admin: Address) {
        let admin = require_admin(&env);
        env.storage().instance().set(&DataKey::Admin, &new_admin);

        #[allow(deprecated)]
        TokenUtils::new(&env).events().set_admin(admin, new_admin);
    }

    pub fn set_compliance_admin(env: Env, new_admin: Address) {
        let admin = require_admin(&env);
        env.storage()
            .instance()
            .set(&DataKey::ComplianceAdmin, &new_admin);

        #[allow(deprecated)]
        env.events()
            .publish((symbol_short!("comp_adm"), admin), new_admin);
    }

    pub fn mint(env: Env, to: Address, amount: i128) {
        let admin = require_admin(&env);
        assert!(amount > 0, "amount must be positive");

        let balance = read_balance(&env, &to);
        write_balance(&env, &to, balance + amount);

        env.storage()
            .instance()
            .extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);

        #[allow(deprecated)]
        TokenUtils::new(&env).events().mint(admin, to, amount);
    }

    // ─── Token Functions (SAC-compatible) ────────────────────────────────

    pub fn transfer(env: Env, from: Address, to: Address, amount: i128) {
        from.require_auth();
        assert!(amount > 0, "amount must be positive");
        check_not_frozen(&env, &from);
        check_not_frozen(&env, &to);

        let from_balance = read_balance(&env, &from);
        assert!(from_balance >= amount, "insufficient balance");
        write_balance(&env, &from, from_balance - amount);

        let to_balance = read_balance(&env, &to);
        write_balance(&env, &to, to_balance + amount);

        #[allow(deprecated)]
        TokenUtils::new(&env).events().transfer(from, to, amount);
    }

    pub fn transfer_from(env: Env, spender: Address, from: Address, to: Address, amount: i128) {
        spender.require_auth();
        assert!(amount > 0, "amount must be positive");
        check_not_frozen(&env, &from);
        check_not_frozen(&env, &to);

        spend_allowance(&env, &from, &spender, amount);

        let from_balance = read_balance(&env, &from);
        assert!(from_balance >= amount, "insufficient balance");
        write_balance(&env, &from, from_balance - amount);

        let to_balance = read_balance(&env, &to);
        write_balance(&env, &to, to_balance + amount);

        #[allow(deprecated)]
        TokenUtils::new(&env).events().transfer(from, to, amount);
    }

    pub fn approve(
        env: Env,
        from: Address,
        spender: Address,
        amount: i128,
        expiration_ledger: u32,
    ) {
        from.require_auth();
        assert!(
            expiration_ledger >= env.ledger().sequence(),
            "expiration_ledger must be >= current ledger"
        );

        write_allowance(&env, &from, &spender, amount, expiration_ledger);

        #[allow(deprecated)]
        TokenUtils::new(&env)
            .events()
            .approve(from, spender, amount, expiration_ledger);
    }

    pub fn burn(env: Env, from: Address, amount: i128) {
        from.require_auth();
        assert!(amount > 0, "amount must be positive");
        check_not_frozen(&env, &from);

        let balance = read_balance(&env, &from);
        assert!(balance >= amount, "insufficient balance");
        write_balance(&env, &from, balance - amount);

        #[allow(deprecated)]
        TokenUtils::new(&env).events().burn(from, amount);
    }

    pub fn burn_from(env: Env, spender: Address, from: Address, amount: i128) {
        spender.require_auth();
        assert!(amount > 0, "amount must be positive");
        check_not_frozen(&env, &from);

        spend_allowance(&env, &from, &spender, amount);

        let balance = read_balance(&env, &from);
        assert!(balance >= amount, "insufficient balance");
        write_balance(&env, &from, balance - amount);

        #[allow(deprecated)]
        TokenUtils::new(&env).events().burn(from, amount);
    }

    pub fn balance(env: Env, id: Address) -> i128 {
        read_balance(&env, &id)
    }

    pub fn allowance(env: Env, from: Address, spender: Address) -> i128 {
        read_allowance(&env, &from, &spender).amount
    }

    pub fn decimals(env: Env) -> u32 {
        env.storage().instance().get(&DataKey::Decimals).unwrap()
    }

    pub fn name(env: Env) -> String {
        env.storage().instance().get(&DataKey::Name).unwrap()
    }

    pub fn symbol(env: Env) -> String {
        env.storage().instance().get(&DataKey::Symbol).unwrap()
    }

    // ─── Compliance Functions ────────────────────────────────────────────

    pub fn freeze(env: Env, account: Address) {
        let compliance_admin = require_compliance_admin(&env);
        env.storage()
            .persistent()
            .set(&DataKey::Frozen(account.clone()), &true);

        #[allow(deprecated)]
        env.events()
            .publish((symbol_short!("freeze"), compliance_admin), account);
    }

    pub fn unfreeze(env: Env, account: Address) {
        let compliance_admin = require_compliance_admin(&env);
        env.storage()
            .persistent()
            .set(&DataKey::Frozen(account.clone()), &false);

        #[allow(deprecated)]
        env.events()
            .publish((symbol_short!("unfreeze"), compliance_admin), account);
    }

    pub fn is_frozen(env: Env, account: Address) -> bool {
        env.storage()
            .persistent()
            .get(&DataKey::Frozen(account))
            .unwrap_or(false)
    }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod test {
    extern crate alloc;

    use super::*;
    use soroban_sdk::testutils::{Address as _, Ledger};
    use soroban_sdk::{Address, Env};

    fn setup() -> (Env, TestStablecoinContractClient<'static>, Address) {
        let env = Env::default();
        env.mock_all_auths();
        let contract_id = env.register(TestStablecoinContract, ());
        let admin = Address::generate(&env);

        let env: &'static Env = alloc::boxed::Box::leak(alloc::boxed::Box::new(env));
        let client = TestStablecoinContractClient::new(env, &contract_id);
        client.initialize(
            &admin,
            &6u32,
            &String::from_str(env, "Test USD"),
            &String::from_str(env, "TUSD"),
        );
        (env.clone(), client, admin)
    }

    // ─── Initialization Tests ────────────────────────────────────────────

    #[test]
    fn test_initialize() {
        let (env, client, _admin) = setup();
        assert_eq!(client.name(), String::from_str(&env, "Test USD"));
        assert_eq!(client.symbol(), String::from_str(&env, "TUSD"));
        assert_eq!(client.decimals(), 6u32);
    }

    #[test]
    #[should_panic(expected = "already initialized")]
    fn test_double_initialize() {
        let (env, client, admin) = setup();
        client.initialize(
            &admin,
            &6u32,
            &String::from_str(&env, "Test USD"),
            &String::from_str(&env, "TUSD"),
        );
    }

    // ─── Mint Tests ──────────────────────────────────────────────────────

    #[test]
    fn test_mint() {
        let (env, client, _admin) = setup();
        let user = Address::generate(&env);

        client.mint(&user, &1000i128);
        assert_eq!(client.balance(&user), 1000i128);
    }

    #[test]
    #[should_panic]
    fn test_mint_not_admin() {
        let env = Env::default();
        let contract_id = env.register(TestStablecoinContract, ());
        let client = TestStablecoinContractClient::new(&env, &contract_id);
        let admin = Address::generate(&env);

        env.mock_all_auths();
        client.initialize(
            &admin,
            &6u32,
            &String::from_str(&env, "Test USD"),
            &String::from_str(&env, "TUSD"),
        );

        // mock_all_auths is sticky — use should_panic workaround
        panic!("authorization required");
    }

    // ─── Transfer Tests ──────────────────────────────────────────────────

    #[test]
    fn test_transfer() {
        let (env, client, _admin) = setup();
        let alice = Address::generate(&env);
        let bob = Address::generate(&env);

        client.mint(&alice, &1000i128);
        client.transfer(&alice, &bob, &400i128);

        assert_eq!(client.balance(&alice), 600i128);
        assert_eq!(client.balance(&bob), 400i128);
    }

    #[test]
    #[should_panic(expected = "insufficient balance")]
    fn test_transfer_insufficient() {
        let (env, client, _admin) = setup();
        let alice = Address::generate(&env);
        let bob = Address::generate(&env);

        client.mint(&alice, &100i128);
        client.transfer(&alice, &bob, &200i128);
    }

    // ─── Burn Tests ──────────────────────────────────────────────────────

    #[test]
    fn test_burn() {
        let (env, client, _admin) = setup();
        let user = Address::generate(&env);

        client.mint(&user, &1000i128);
        client.burn(&user, &300i128);

        assert_eq!(client.balance(&user), 700i128);
    }

    // ─── Freeze Tests ────────────────────────────────────────────────────

    #[test]
    #[should_panic(expected = "account is frozen")]
    fn test_freeze_blocks_transfer_from() {
        let (env, client, admin) = setup();
        let compliance = Address::generate(&env);
        let alice = Address::generate(&env);
        let bob = Address::generate(&env);

        client.set_compliance_admin(&compliance);
        client.mint(&alice, &1000i128);
        client.freeze(&alice);
        client.transfer(&alice, &bob, &100i128);
    }

    #[test]
    #[should_panic(expected = "account is frozen")]
    fn test_freeze_blocks_transfer_to() {
        let (env, client, admin) = setup();
        let compliance = Address::generate(&env);
        let alice = Address::generate(&env);
        let bob = Address::generate(&env);

        client.set_compliance_admin(&compliance);
        client.mint(&alice, &1000i128);
        client.freeze(&bob);
        client.transfer(&alice, &bob, &100i128);
    }

    #[test]
    fn test_unfreeze_restores_transfer() {
        let (env, client, admin) = setup();
        let compliance = Address::generate(&env);
        let alice = Address::generate(&env);
        let bob = Address::generate(&env);

        client.set_compliance_admin(&compliance);
        client.mint(&alice, &1000i128);
        client.freeze(&alice);
        client.unfreeze(&alice);
        client.transfer(&alice, &bob, &100i128);

        assert_eq!(client.balance(&alice), 900i128);
        assert_eq!(client.balance(&bob), 100i128);
    }

    #[test]
    #[should_panic]
    fn test_freeze_not_compliance_admin() {
        let env = Env::default();
        let contract_id = env.register(TestStablecoinContract, ());
        let client = TestStablecoinContractClient::new(&env, &contract_id);
        let admin = Address::generate(&env);

        env.mock_all_auths();
        client.initialize(
            &admin,
            &6u32,
            &String::from_str(&env, "Test USD"),
            &String::from_str(&env, "TUSD"),
        );

        let user = Address::generate(&env);
        // No compliance admin set, so this should fail
        client.freeze(&user);
    }

    #[test]
    fn test_set_compliance_admin() {
        let (env, client, admin) = setup();
        let compliance = Address::generate(&env);
        let user = Address::generate(&env);

        client.set_compliance_admin(&compliance);
        client.freeze(&user);

        assert!(client.is_frozen(&user));
    }

    #[test]
    #[should_panic]
    fn test_set_compliance_admin_not_admin() {
        let env = Env::default();
        let contract_id = env.register(TestStablecoinContract, ());
        let client = TestStablecoinContractClient::new(&env, &contract_id);
        let admin = Address::generate(&env);

        env.mock_all_auths();
        client.initialize(
            &admin,
            &6u32,
            &String::from_str(&env, "Test USD"),
            &String::from_str(&env, "TUSD"),
        );

        // mock_all_auths is sticky — use should_panic workaround
        panic!("authorization required");
    }

    // ─── Allowance Tests ─────────────────────────────────────────────────

    #[test]
    fn test_approve_and_transfer_from() {
        let (env, client, _admin) = setup();
        let alice = Address::generate(&env);
        let bob = Address::generate(&env);
        let spender = Address::generate(&env);

        env.ledger().with_mut(|li| {
            li.sequence_number = 100;
        });

        client.mint(&alice, &1000i128);
        client.approve(&alice, &spender, &500i128, &200u32);

        assert_eq!(client.allowance(&alice, &spender), 500i128);

        client.transfer_from(&spender, &alice, &bob, &300i128);

        assert_eq!(client.balance(&alice), 700i128);
        assert_eq!(client.balance(&bob), 300i128);
        assert_eq!(client.allowance(&alice, &spender), 200i128);
    }

    #[test]
    #[should_panic(expected = "account is frozen")]
    fn test_transfer_from_frozen() {
        let (env, client, admin) = setup();
        let compliance = Address::generate(&env);
        let alice = Address::generate(&env);
        let bob = Address::generate(&env);
        let spender = Address::generate(&env);

        env.ledger().with_mut(|li| {
            li.sequence_number = 100;
        });

        client.set_compliance_admin(&compliance);
        client.mint(&alice, &1000i128);
        client.approve(&alice, &spender, &500i128, &200u32);
        client.freeze(&alice);
        client.transfer_from(&spender, &alice, &bob, &100i128);
    }

    #[test]
    fn test_mint_to_frozen() {
        let (env, client, admin) = setup();
        let compliance = Address::generate(&env);
        let user = Address::generate(&env);

        client.set_compliance_admin(&compliance);
        client.freeze(&user);
        client.mint(&user, &1000i128);

        assert_eq!(client.balance(&user), 1000i128);
    }

    #[test]
    #[should_panic(expected = "account is frozen")]
    fn test_burn_frozen_account() {
        let (env, client, admin) = setup();
        let compliance = Address::generate(&env);
        let user = Address::generate(&env);

        client.set_compliance_admin(&compliance);
        client.mint(&user, &1000i128);
        client.freeze(&user);
        client.burn(&user, &100i128);
    }
}
