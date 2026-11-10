#![no_std]

use soroban_sdk::{
    contract, contracterror, contractimpl, panic_with_error, symbol_short, Address, Env,
    MuxedAddress, String, Symbol, Vec,
};
use stellar_access::access_control::{self as access_control, AccessControl};
use stellar_tokens::fungible::{
    allowlist::AllowList, blocklist::BlockList, burnable::FungibleBurnable, Base,
    ContractOverrides, FungibleToken, FungibleTokenError, INSTANCE_EXTEND_AMOUNT,
    INSTANCE_TTL_THRESHOLD,
};

pub const ONBOARDER_ROLE: Symbol = symbol_short!("onboarder");
pub const BLOCKER_ROLE: Symbol = symbol_short!("blocker");
pub const UNBLOCKER_ROLE: Symbol = symbol_short!("unblocker");

pub const MAX_BATCH_SIZE: u32 = 40;

const DECIMALS: u32 = 6;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum OnboardableTokenError {
    BatchTooLargeError = 102,
    UserBlockedError = 105,
}

fn extend_instance_ttl(e: &Env) {
    e.storage()
        .instance()
        .extend_ttl(INSTANCE_TTL_THRESHOLD, INSTANCE_EXTEND_AMOUNT);
}

fn authorize_operator(e: &Env, operator: &Address, role: &Symbol) {
    access_control::ensure_role(e, role, operator);
    operator.require_auth();
    extend_instance_ttl(e);
}

fn authorize_batch_operator(e: &Env, users: &Vec<Address>, operator: &Address, role: &Symbol) {
    authorize_operator(e, operator, role);
    if users.len() > MAX_BATCH_SIZE {
        panic_with_error!(e, OnboardableTokenError::BatchTooLargeError);
    }
}

fn has_role(e: &Env, account: &Address, role: &Symbol) -> bool {
    access_control::has_role(e, account, role).is_some()
}

fn revert_if_blocked(e: &Env, account: &Address) {
    if BlockList::blocked(e, account) {
        panic_with_error!(e, FungibleTokenError::UserBlocked);
    }
}

fn revert_if_not_onboarded(e: &Env, account: &Address) {
    if !AllowList::allowed(e, account) {
        panic_with_error!(e, FungibleTokenError::UserNotAllowed);
    }
}

fn revert_unless_transferable(e: &Env, from: &Address, to: &Address) {
    revert_if_blocked(e, from);
    revert_if_blocked(e, to);
    revert_if_not_onboarded(e, from);
    revert_if_not_onboarded(e, to);
    extend_instance_ttl(e);
}

pub struct Onboardable;

impl ContractOverrides for Onboardable {
    fn transfer(e: &Env, from: &Address, to: &MuxedAddress, amount: i128) {
        revert_unless_transferable(e, from, &to.address());
        Base::transfer(e, from, to, amount);
    }

    fn transfer_from(e: &Env, spender: &Address, from: &Address, to: &Address, amount: i128) {
        revert_unless_transferable(e, from, to);
        Base::transfer_from(e, spender, from, to, amount);
    }
}

#[contract]
pub struct OnboardableTokenContract;

#[contractimpl]
impl OnboardableTokenContract {
    pub fn __constructor(
        e: &Env,
        name: String,
        symbol: String,
        admin: Address,
        onboarder: Address,
        block_operator: Address,
        unblock_operator: Address,
    ) {
        Base::set_metadata(e, DECIMALS, name, symbol);
        access_control::set_admin(e, &admin);
        access_control::grant_role_no_auth(e, &onboarder, &ONBOARDER_ROLE, &admin);
        access_control::grant_role_no_auth(e, &block_operator, &BLOCKER_ROLE, &admin);
        access_control::grant_role_no_auth(e, &unblock_operator, &UNBLOCKER_ROLE, &admin);
        extend_instance_ttl(e);
    }

    pub fn mint(e: &Env, to: Address, amount: i128) {
        access_control::enforce_admin_auth(e);
        revert_if_blocked(e, &to);
        revert_if_not_onboarded(e, &to);
        extend_instance_ttl(e);
        Base::mint(e, &to, amount);
    }

    pub fn onboard_user(e: &Env, user: Address, operator: Address) {
        authorize_operator(e, &operator, &ONBOARDER_ROLE);
        if BlockList::blocked(e, &user) {
            panic_with_error!(e, OnboardableTokenError::UserBlockedError);
        }
        AllowList::allow_user(e, &user);
    }

    pub fn offboard_user(e: &Env, user: Address, operator: Address) {
        authorize_operator(e, &operator, &ONBOARDER_ROLE);
        AllowList::disallow_user(e, &user);
    }

    pub fn block_user(e: &Env, user: Address, operator: Address) {
        authorize_operator(e, &operator, &BLOCKER_ROLE);
        BlockList::block_user(e, &user);
    }

    pub fn unblock_user(e: &Env, user: Address, operator: Address) {
        authorize_operator(e, &operator, &UNBLOCKER_ROLE);
        BlockList::unblock_user(e, &user);
    }

    pub fn batch_onboard_users(e: &Env, users: Vec<Address>, operator: Address) -> Vec<Address> {
        authorize_batch_operator(e, &users, &operator, &ONBOARDER_ROLE);
        let mut blocked = Vec::new(e);
        for user in users.iter() {
            if BlockList::blocked(e, &user) {
                blocked.push_back(user);
            } else {
                AllowList::allow_user(e, &user);
            }
        }
        blocked
    }

    pub fn batch_offboard_users(e: &Env, users: Vec<Address>, operator: Address) {
        authorize_batch_operator(e, &users, &operator, &ONBOARDER_ROLE);
        for user in users.iter() {
            AllowList::disallow_user(e, &user);
        }
    }

    pub fn batch_block_users(e: &Env, users: Vec<Address>, operator: Address) {
        authorize_batch_operator(e, &users, &operator, &BLOCKER_ROLE);
        for user in users.iter() {
            BlockList::block_user(e, &user);
        }
    }

    pub fn batch_unblock_users(e: &Env, users: Vec<Address>, operator: Address) {
        authorize_batch_operator(e, &users, &operator, &UNBLOCKER_ROLE);
        for user in users.iter() {
            BlockList::unblock_user(e, &user);
        }
    }

    pub fn is_onboarded(e: &Env, account: Address) -> bool {
        AllowList::allowed(e, &account)
    }

    pub fn is_on_block_list(e: &Env, account: Address) -> bool {
        BlockList::blocked(e, &account)
    }

    pub fn is_onboarder(e: &Env, account: Address) -> bool {
        has_role(e, &account, &ONBOARDER_ROLE)
    }

    pub fn is_block_operator(e: &Env, account: Address) -> bool {
        has_role(e, &account, &BLOCKER_ROLE)
    }

    pub fn is_unblock_operator(e: &Env, account: Address) -> bool {
        has_role(e, &account, &UNBLOCKER_ROLE)
    }
}

#[contractimpl(contracttrait)]
impl FungibleToken for OnboardableTokenContract {
    type ContractType = Onboardable;
}

#[contractimpl(contracttrait)]
impl FungibleBurnable for OnboardableTokenContract {
    fn burn(e: &Env, from: Address, amount: i128) {
        BlockList::burn(e, &from, amount);
    }

    fn burn_from(e: &Env, spender: Address, from: Address, amount: i128) {
        BlockList::burn_from(e, &spender, &from, amount);
    }
}

#[contractimpl(contracttrait)]
impl AccessControl for OnboardableTokenContract {}

#[cfg(test)]
mod test {
    extern crate std;

    use soroban_sdk::{
        testutils::{Address as _, Events as _, MockAuth, MockAuthInvoke},
        Address, Env, Error, Event, IntoVal, String, Val,
    };
    use stellar_tokens::fungible::{
        allowlist::{UserAllowed, UserDisallowed},
        blocklist::UserBlocked,
    };

    use super::*;

    const AMOUNT: i128 = 1_000_000_000;

    struct Setup {
        env: Env,
        token: OnboardableTokenContractClient<'static>,
        admin: Address,
        onboarder: Address,
        blocker: Address,
        unblocker: Address,
        alice: Address,
        bob: Address,
    }

    fn setup() -> Setup {
        let env = Env::default();
        env.mock_all_auths();

        let admin = Address::generate(&env);
        let onboarder = Address::generate(&env);
        let blocker = Address::generate(&env);
        let unblocker = Address::generate(&env);
        let address = env.register(
            OnboardableTokenContract,
            (
                String::from_str(&env, "Onboardable USD"),
                String::from_str(&env, "oUSD"),
                &admin,
                &onboarder,
                &blocker,
                &unblocker,
            ),
        );
        let token = OnboardableTokenContractClient::new(&env, &address);
        let alice = Address::generate(&env);
        let bob = Address::generate(&env);

        Setup {
            env,
            token,
            admin,
            onboarder,
            blocker,
            unblocker,
            alice,
            bob,
        }
    }

    fn token_events(s: &Setup) -> std::vec::Vec<(Address, soroban_sdk::Vec<Val>, Val)> {
        s.env
            .events()
            .all()
            .iter()
            .filter(|(address, _, _)| address == &s.token.address)
            .collect()
    }

    fn assert_last_event<E: Event>(s: &Setup, expected: &E) {
        let events = token_events(s);
        let (_, topics, _) = events.last().expect("expected token event");
        assert_eq!(topics, &expected.topics(&s.env));
    }

    fn token_error(error: FungibleTokenError) -> Error {
        error.into()
    }

    fn gateway_error(error: OnboardableTokenError) -> Error {
        error.into()
    }

    fn access_error(error: access_control::AccessControlError) -> Error {
        error.into()
    }

    #[test]
    fn metadata_and_roles_are_set_at_deploy() {
        let s = setup();

        assert_eq!(s.token.decimals(), 6);
        assert_eq!(s.token.name(), String::from_str(&s.env, "Onboardable USD"));
        assert_eq!(s.token.symbol(), String::from_str(&s.env, "oUSD"));
        assert_eq!(s.token.get_admin(), Some(s.admin.clone()));
        assert!(s.token.is_onboarder(&s.onboarder));
        assert!(s.token.is_block_operator(&s.blocker));
        assert!(s.token.is_unblock_operator(&s.unblocker));
    }

    #[test]
    fn role_views_identify_only_their_configured_roles() {
        let s = setup();

        assert!(!s.token.is_onboarder(&s.blocker));
        assert!(!s.token.is_onboarder(&s.admin));
        assert!(!s.token.is_block_operator(&s.onboarder));
        assert!(!s.token.is_unblock_operator(&s.blocker));
    }

    #[test]
    fn one_wallet_can_hold_every_operator_role() {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let operator = Address::generate(&env);
        let address = env.register(
            OnboardableTokenContract,
            (
                String::from_str(&env, "Onboardable USD"),
                String::from_str(&env, "oUSD"),
                &admin,
                &operator,
                &operator,
                &operator,
            ),
        );
        let token = OnboardableTokenContractClient::new(&env, &address);
        let user = Address::generate(&env);

        token.onboard_user(&user, &operator);
        token.block_user(&user, &operator);
        token.unblock_user(&user, &operator);
        token.offboard_user(&user, &operator);

        assert!(!token.is_onboarded(&user));
        assert!(!token.is_on_block_list(&user));
    }

    #[test]
    fn fresh_address_is_not_onboarded_or_blocked() {
        let s = setup();

        assert!(!s.token.is_onboarded(&s.alice));
        assert!(!s.token.is_on_block_list(&s.alice));
    }

    #[test]
    fn onboard_user_allows_and_emits() {
        let s = setup();

        s.token.onboard_user(&s.alice, &s.onboarder);

        assert_last_event(
            &s,
            &UserAllowed {
                user: s.alice.clone(),
            },
        );
        assert!(s.token.is_onboarded(&s.alice));
    }

    #[test]
    fn repeated_onboarding_is_silent_noop() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);

        s.token.onboard_user(&s.alice, &s.onboarder);

        assert!(s.token.is_onboarded(&s.alice));
        assert!(token_events(&s).is_empty());
    }

    #[test]
    fn offboard_user_disallows_and_emits() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);

        s.token.offboard_user(&s.alice, &s.onboarder);

        assert_last_event(
            &s,
            &UserDisallowed {
                user: s.alice.clone(),
            },
        );
        assert!(!s.token.is_onboarded(&s.alice));
    }

    #[test]
    fn offboarding_unlisted_address_is_silent_noop() {
        let s = setup();

        s.token.offboard_user(&s.alice, &s.onboarder);

        assert!(token_events(&s).is_empty());
    }

    #[test]
    fn onboarding_requires_onboarder_role() {
        let s = setup();
        let unauthorized = Err(Ok(access_error(
            access_control::AccessControlError::Unauthorized,
        )));

        assert_eq!(s.token.try_onboard_user(&s.alice, &s.blocker), unauthorized);
        assert_eq!(s.token.try_onboard_user(&s.alice, &s.admin), unauthorized);
        s.token.onboard_user(&s.alice, &s.onboarder);
        assert_eq!(
            s.token.try_offboard_user(&s.alice, &s.blocker),
            unauthorized
        );
        assert!(s.token.is_onboarded(&s.alice));
    }

    #[test]
    fn block_list_requires_its_own_roles() {
        let s = setup();
        let unauthorized = Err(Ok(access_error(
            access_control::AccessControlError::Unauthorized,
        )));

        assert_eq!(s.token.try_block_user(&s.alice, &s.onboarder), unauthorized);
        assert_eq!(s.token.try_block_user(&s.alice, &s.unblocker), unauthorized);
        s.token.block_user(&s.alice, &s.blocker);
        assert_eq!(s.token.try_unblock_user(&s.alice, &s.blocker), unauthorized);
        assert!(s.token.is_on_block_list(&s.alice));
    }

    #[test]
    fn operator_signature_is_required() {
        let s = setup();
        s.env.mock_auths(&[]);

        assert!(s.token.try_onboard_user(&s.alice, &s.onboarder).is_err());
        assert!(s.token.try_offboard_user(&s.alice, &s.onboarder).is_err());
        assert!(s.token.try_block_user(&s.alice, &s.blocker).is_err());
        assert!(s.token.try_unblock_user(&s.alice, &s.unblocker).is_err());
        let users = soroban_sdk::vec![&s.env, s.alice.clone()];
        assert!(s
            .token
            .try_batch_onboard_users(&users, &s.onboarder)
            .is_err());
        assert!(s
            .token
            .try_batch_offboard_users(&users, &s.onboarder)
            .is_err());
        assert!(s.token.try_batch_block_users(&users, &s.blocker).is_err());
        assert!(s
            .token
            .try_batch_unblock_users(&users, &s.unblocker)
            .is_err());
    }

    fn generate_users(env: &Env, count: u32) -> soroban_sdk::Vec<Address> {
        let mut users = soroban_sdk::Vec::new(env);
        for _ in 0..count {
            users.push_back(Address::generate(env));
        }
        users
    }

    #[test]
    fn batch_onboard_users_onboards_each_and_emits_per_user() {
        let s = setup();
        let users = generate_users(&s.env, 3);

        s.token.batch_onboard_users(&users, &s.onboarder);

        let events = token_events(&s);
        assert_eq!(events.len(), 3);
        for (user, (_, topics, _)) in users.iter().zip(events.iter()) {
            assert_eq!(topics, &UserAllowed { user: user.clone() }.topics(&s.env));
            assert!(s.token.is_onboarded(&user));
        }
    }

    #[test]
    fn batch_onboard_users_skips_already_onboarded_and_duplicates() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);
        let users = soroban_sdk::vec![&s.env, s.alice.clone(), s.bob.clone(), s.bob.clone()];

        s.token.batch_onboard_users(&users, &s.onboarder);

        let events = token_events(&s);
        assert_eq!(events.len(), 1);
        assert_last_event(
            &s,
            &UserAllowed {
                user: s.bob.clone(),
            },
        );
        assert!(s.token.is_onboarded(&s.alice));
        assert!(s.token.is_onboarded(&s.bob));
    }

    #[test]
    fn empty_batches_are_silent_noops() {
        let s = setup();
        let users = soroban_sdk::Vec::new(&s.env);

        s.token.batch_onboard_users(&users, &s.onboarder);
        s.token.batch_offboard_users(&users, &s.onboarder);
        s.token.batch_block_users(&users, &s.blocker);
        s.token.batch_unblock_users(&users, &s.unblocker);

        assert!(token_events(&s).is_empty());
    }

    #[test]
    fn batch_offboard_users_offboards_each() {
        let s = setup();
        let users = generate_users(&s.env, 3);
        s.token.batch_onboard_users(&users, &s.onboarder);

        s.token.batch_offboard_users(&users, &s.onboarder);

        assert_eq!(token_events(&s).len(), 3);
        for user in users.iter() {
            assert!(!s.token.is_onboarded(&user));
        }
    }

    #[test]
    fn batch_block_users_and_batch_unblock_users_toggle_each() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);
        s.token.onboard_user(&s.bob, &s.onboarder);
        s.token.mint(&s.alice, &AMOUNT);
        let users = soroban_sdk::vec![&s.env, s.alice.clone(), s.bob.clone()];

        s.token.batch_block_users(&users, &s.blocker);
        assert_eq!(token_events(&s).len(), 2);
        assert!(s.token.is_on_block_list(&s.alice));
        assert!(s.token.is_on_block_list(&s.bob));
        assert_eq!(
            s.token.try_transfer(&s.alice, &s.bob, &1),
            Err(Ok(token_error(FungibleTokenError::UserBlocked)))
        );

        s.token.batch_unblock_users(&users, &s.unblocker);
        assert_eq!(token_events(&s).len(), 2);
        assert!(!s.token.is_on_block_list(&s.alice));
        assert!(!s.token.is_on_block_list(&s.bob));
        s.token.transfer(&s.alice, &s.bob, &400);
        assert_eq!(s.token.balance(&s.bob), 400);
    }

    #[test]
    fn batches_require_their_roles_and_write_nothing_when_refused() {
        let s = setup();
        let users = soroban_sdk::vec![&s.env, s.alice.clone(), s.bob.clone()];
        let unauthorized = Err(Ok(access_error(
            access_control::AccessControlError::Unauthorized,
        )));

        assert_eq!(
            s.token.try_batch_onboard_users(&users, &s.blocker),
            Err(Ok(access_error(
                access_control::AccessControlError::Unauthorized
            )))
        );
        assert_eq!(
            s.token.try_batch_block_users(&users, &s.onboarder),
            unauthorized
        );
        assert_eq!(
            s.token.try_batch_block_users(&users, &s.unblocker),
            unauthorized
        );
        for user in users.iter() {
            assert!(!s.token.is_onboarded(&user));
            assert!(!s.token.is_on_block_list(&user));
        }

        s.token.batch_onboard_users(&users, &s.onboarder);
        s.token.batch_block_users(&users, &s.blocker);
        assert_eq!(
            s.token.try_batch_offboard_users(&users, &s.blocker),
            unauthorized
        );
        assert_eq!(
            s.token.try_batch_unblock_users(&users, &s.blocker),
            unauthorized
        );
        for user in users.iter() {
            assert!(s.token.is_onboarded(&user));
            assert!(s.token.is_on_block_list(&user));
        }
    }

    #[test]
    fn admin_can_rotate_the_onboarder_role() {
        let s = setup();
        let replacement = Address::generate(&s.env);

        s.token.grant_role(&replacement, &ONBOARDER_ROLE, &s.admin);
        s.token.revoke_role(&s.onboarder, &ONBOARDER_ROLE, &s.admin);

        assert!(s.token.is_onboarder(&replacement));
        assert!(!s.token.is_onboarder(&s.onboarder));
        assert!(s.token.try_onboard_user(&s.alice, &s.onboarder).is_err());
        s.token.onboard_user(&s.alice, &replacement);
        assert!(s.token.is_onboarded(&s.alice));
    }

    #[test]
    fn mint_to_unlisted_address_reverts() {
        let s = setup();

        assert_eq!(
            s.token.try_mint(&s.alice, &AMOUNT),
            Err(Ok(token_error(FungibleTokenError::UserNotAllowed)))
        );
    }

    #[test]
    fn mint_to_onboarded_address_succeeds() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);

        s.token.mint(&s.alice, &AMOUNT);

        assert_eq!(s.token.balance(&s.alice), AMOUNT);
        assert_eq!(s.token.total_supply(), AMOUNT);
    }

    #[test]
    fn mint_requires_admin_signature() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);
        s.env.mock_auths(&[]);

        assert!(s.token.try_mint(&s.alice, &AMOUNT).is_err());
    }

    #[test]
    fn transfer_to_unlisted_address_reverts() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);
        s.token.mint(&s.alice, &AMOUNT);

        assert_eq!(
            s.token.try_transfer(&s.alice, &s.bob, &1),
            Err(Ok(token_error(FungibleTokenError::UserNotAllowed)))
        );
        assert_eq!(s.token.balance(&s.bob), 0);
    }

    #[test]
    fn full_onboarding_lifecycle() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);
        s.token.onboard_user(&s.bob, &s.onboarder);
        s.token.mint(&s.alice, &AMOUNT);

        s.token.transfer(&s.alice, &s.bob, &400);
        assert_eq!(s.token.balance(&s.bob), 400);

        s.token.offboard_user(&s.alice, &s.onboarder);
        assert_eq!(
            s.token.try_transfer(&s.alice, &s.bob, &1),
            Err(Ok(token_error(FungibleTokenError::UserNotAllowed)))
        );
        assert_eq!(
            s.token.try_transfer(&s.bob, &s.alice, &1),
            Err(Ok(token_error(FungibleTokenError::UserNotAllowed)))
        );

        s.token.onboard_user(&s.alice, &s.onboarder);
        s.token.transfer(&s.bob, &s.alice, &400);
        assert_eq!(s.token.balance(&s.alice), AMOUNT);
    }

    #[test]
    fn transfer_from_checks_owner_and_recipient() {
        let s = setup();
        let spender = Address::generate(&s.env);
        let live_until = s.env.ledger().sequence() + 1_000;
        s.token.onboard_user(&s.alice, &s.onboarder);
        s.token.mint(&s.alice, &AMOUNT);
        s.token.approve(&s.alice, &spender, &AMOUNT, &live_until);

        assert_eq!(
            s.token.try_transfer_from(&spender, &s.alice, &s.bob, &1),
            Err(Ok(token_error(FungibleTokenError::UserNotAllowed)))
        );

        s.token.onboard_user(&s.bob, &s.onboarder);
        s.token.transfer_from(&spender, &s.alice, &s.bob, &250);
        assert_eq!(s.token.balance(&s.bob), 250);

        s.token.offboard_user(&s.alice, &s.onboarder);
        assert_eq!(
            s.token.try_transfer_from(&spender, &s.alice, &s.bob, &1),
            Err(Ok(token_error(FungibleTokenError::UserNotAllowed)))
        );
    }

    #[test]
    fn burn_ignores_onboarding() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);
        s.token.mint(&s.alice, &AMOUNT);
        s.token.offboard_user(&s.alice, &s.onboarder);

        s.token.burn(&s.alice, &AMOUNT);

        assert_eq!(s.token.balance(&s.alice), 0);
        assert_eq!(s.token.total_supply(), 0);
    }

    #[test]
    fn block_list_applies_to_onboarded_accounts() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);
        s.token.onboard_user(&s.bob, &s.onboarder);
        s.token.mint(&s.alice, &AMOUNT);

        s.token.block_user(&s.alice, &s.blocker);
        assert_last_event(
            &s,
            &UserBlocked {
                user: s.alice.clone(),
            },
        );
        assert!(s.token.is_onboarded(&s.alice));
        let blocked = Err(Ok(token_error(FungibleTokenError::UserBlocked)));
        assert_eq!(s.token.try_transfer(&s.alice, &s.bob, &1), blocked);
        assert_eq!(s.token.try_transfer(&s.bob, &s.alice, &1), blocked);
        assert_eq!(s.token.try_burn(&s.alice, &1), blocked);

        s.token.unblock_user(&s.alice, &s.unblocker);
        s.token.transfer(&s.alice, &s.bob, &400);
        assert_eq!(s.token.balance(&s.bob), 400);
    }

    #[test]
    fn blocked_onboarded_recipient_cannot_receive_mint() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);
        s.token.block_user(&s.alice, &s.blocker);

        assert_eq!(
            s.token.try_mint(&s.alice, &AMOUNT),
            Err(Ok(token_error(FungibleTokenError::UserBlocked)))
        );
        assert_eq!(s.token.balance(&s.alice), 0);
    }

    #[test]
    fn onboarding_block_listed_user_returns_user_blocked_error() {
        let s = setup();
        s.token.block_user(&s.alice, &s.blocker);

        assert_eq!(
            s.token.try_onboard_user(&s.alice, &s.onboarder),
            Err(Ok(gateway_error(OnboardableTokenError::UserBlockedError)))
        );
        assert!(!s.token.is_onboarded(&s.alice));

        s.token.unblock_user(&s.alice, &s.unblocker);
        s.token.onboard_user(&s.alice, &s.onboarder);
        assert!(s.token.is_onboarded(&s.alice));
    }

    #[test]
    fn blocking_an_onboarded_user_keeps_the_onboarding() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);

        s.token.block_user(&s.alice, &s.blocker);
        assert!(s.token.is_onboarded(&s.alice));
        assert!(s.token.is_on_block_list(&s.alice));

        s.token.unblock_user(&s.alice, &s.unblocker);
        assert!(s.token.is_onboarded(&s.alice));
        assert!(!s.token.is_on_block_list(&s.alice));
    }

    #[test]
    fn error_codes_match_the_supported_interface() {
        assert_eq!(OnboardableTokenError::BatchTooLargeError as u32, 102);
        assert_eq!(OnboardableTokenError::UserBlockedError as u32, 105);
    }

    #[test]
    fn batch_onboard_users_skips_and_returns_block_listed_users() {
        let s = setup();
        let carol = Address::generate(&s.env);
        s.token.block_user(&s.bob, &s.blocker);
        let users = soroban_sdk::vec![&s.env, s.alice.clone(), s.bob.clone(), carol.clone()];

        let blocked = s.token.batch_onboard_users(&users, &s.onboarder);

        assert_eq!(blocked, soroban_sdk::vec![&s.env, s.bob.clone()]);
        assert!(s.token.is_onboarded(&s.alice));
        assert!(!s.token.is_onboarded(&s.bob));
        assert!(s.token.is_onboarded(&carol));
    }

    #[test]
    fn batches_accept_up_to_max_batch_size() {
        let s = setup();
        let users = generate_users(&s.env, MAX_BATCH_SIZE);

        assert!(s.token.batch_onboard_users(&users, &s.onboarder).is_empty());
        s.token.batch_block_users(&users, &s.blocker);
        s.token.batch_unblock_users(&users, &s.unblocker);
        s.token.batch_offboard_users(&users, &s.onboarder);

        for user in users.iter() {
            assert!(!s.token.is_onboarded(&user));
            assert!(!s.token.is_on_block_list(&user));
        }
    }

    #[test]
    fn batches_over_max_batch_size_are_refused() {
        let s = setup();
        let users = generate_users(&s.env, MAX_BATCH_SIZE + 1);
        let too_large = Err(Ok(gateway_error(OnboardableTokenError::BatchTooLargeError)));

        assert_eq!(
            s.token.try_batch_onboard_users(&users, &s.onboarder),
            Err(Ok(gateway_error(OnboardableTokenError::BatchTooLargeError)))
        );
        assert_eq!(
            s.token.try_batch_offboard_users(&users, &s.onboarder),
            too_large
        );
        assert_eq!(s.token.try_batch_block_users(&users, &s.blocker), too_large);
        assert_eq!(
            s.token.try_batch_unblock_users(&users, &s.unblocker),
            too_large
        );
        for user in users.iter() {
            assert!(!s.token.is_onboarded(&user));
            assert!(!s.token.is_on_block_list(&user));
        }
    }

    #[test]
    fn operator_roles_cannot_mint() {
        let s = setup();
        s.token.onboard_user(&s.alice, &s.onboarder);
        s.env.mock_auths(&[MockAuth {
            address: &s.onboarder,
            invoke: &MockAuthInvoke {
                contract: &s.token.address,
                fn_name: "mint",
                args: (&s.alice, AMOUNT).into_val(&s.env),
                sub_invokes: &[],
            },
        }]);

        assert!(s.token.try_mint(&s.alice, &AMOUNT).is_err());
        assert_eq!(s.token.balance(&s.alice), 0);
    }
}
