#![no_std]
//! Test-only SAC administration contract for onboarding and compliance holds.
//!
//! This crate is intentionally limited to integration testing. It is unaudited,
//! is not production-ready, and must not be used to administer assets of value.

use soroban_sdk::{
    contract, contracterror, contractevent, contractimpl, contracttype, panic_with_error, token,
    Address, Env,
};

const DAY_IN_LEDGERS: u32 = 17_280;
const INSTANCE_BUMP_AMOUNT: u32 = 30 * DAY_IN_LEDGERS;
const INSTANCE_LIFETIME_THRESHOLD: u32 = INSTANCE_BUMP_AMOUNT - DAY_IN_LEDGERS;
const PERSISTENT_BUMP_AMOUNT: u32 = 365 * DAY_IN_LEDGERS;
const PERSISTENT_LIFETIME_THRESHOLD: u32 = PERSISTENT_BUMP_AMOUNT - 30 * DAY_IN_LEDGERS;

#[contract]
pub struct TestSacAdminContract;

/// Errors returned by the test SAC administrator.
#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum TestSacAdminError {
    AlreadyInitialized = 1,
    NotInitialized = 2,
    Unauthorized = 3,
    InvalidAmount = 4,
    DestinationNotAuthorized = 6,
    UserBlockedError = 105,
}

#[derive(Clone)]
#[contracttype]
enum DataKey {
    SacToken,
    Minter,
    Onboarder,
    BlockOperator,
    UnblockOperator,
    Onboarded(Address),
    BlockListed(Address),
}

/// Emitted the first time an address is approved by the onboarder.
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserOnboarded {
    #[topic]
    pub user: Address,
}

/// Emitted when an address is placed on the compliance block list.
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserBlocked {
    #[topic]
    pub user: Address,
}

/// Emitted when an address is removed from the compliance block list.
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UserUnblocked {
    #[topic]
    pub user: Address,
}

fn extend_instance_ttl(e: &Env) {
    e.storage()
        .instance()
        .extend_ttl(INSTANCE_LIFETIME_THRESHOLD, INSTANCE_BUMP_AMOUNT);
}

fn read_instance_address(e: &Env, key: &DataKey) -> Address {
    match e.storage().instance().get(key) {
        Some(address) => address,
        None => panic_with_error!(e, TestSacAdminError::NotInitialized),
    }
}

fn require_role(e: &Env, operator: &Address, key: &DataKey) -> Result<(), TestSacAdminError> {
    operator.require_auth();
    if operator != &read_instance_address(e, key) {
        return Err(TestSacAdminError::Unauthorized);
    }
    Ok(())
}

fn persistent_entry_exists(e: &Env, key: &DataKey) -> bool {
    if !e.storage().persistent().has(key) {
        return false;
    }
    e.storage()
        .persistent()
        .extend_ttl(key, PERSISTENT_LIFETIME_THRESHOLD, PERSISTENT_BUMP_AMOUNT);
    true
}

fn set_persistent_entry(e: &Env, key: &DataKey) {
    e.storage().persistent().set(key, &());
    e.storage()
        .persistent()
        .extend_ttl(key, PERSISTENT_LIFETIME_THRESHOLD, PERSISTENT_BUMP_AMOUNT);
}

fn is_onboarded(e: &Env, account: &Address) -> bool {
    persistent_entry_exists(e, &DataKey::Onboarded(account.clone()))
}

fn is_on_block_list(e: &Env, account: &Address) -> bool {
    persistent_entry_exists(e, &DataKey::BlockListed(account.clone()))
}

fn sac_is_authorized(e: &Env, account: &Address) -> bool {
    let sac = read_instance_address(e, &DataKey::SacToken);
    matches!(
        token::StellarAssetClient::new(e, &sac).try_authorized(account),
        Ok(Ok(true))
    )
}

#[contractimpl]
impl TestSacAdminContract {
    /// Initializes the test wrapper and its fixed operator addresses.
    ///
    /// Every operator argument may be the same address for single-wallet tests.
    pub fn __constructor(
        e: &Env,
        sac_token: Address,
        minter: Address,
        onboarder: Address,
        block_operator: Address,
        unblock_operator: Address,
    ) -> Result<(), TestSacAdminError> {
        if e.storage().instance().has(&DataKey::SacToken) {
            return Err(TestSacAdminError::AlreadyInitialized);
        }

        e.storage().instance().set(&DataKey::SacToken, &sac_token);
        e.storage().instance().set(&DataKey::Minter, &minter);
        e.storage().instance().set(&DataKey::Onboarder, &onboarder);
        e.storage()
            .instance()
            .set(&DataKey::BlockOperator, &block_operator);
        e.storage()
            .instance()
            .set(&DataKey::UnblockOperator, &unblock_operator);
        extend_instance_ttl(e);
        Ok(())
    }

    /// Approves an address for SAC use and records permanent onboarding history.
    ///
    /// Re-onboarding restores SAC authorization after trustline recreation but
    /// emits [`UserOnboarded`] only for the first successful onboarding.
    ///
    /// # Errors
    ///
    /// Returns [`TestSacAdminError::UserBlockedError`] while the address is on the
    /// compliance block list.
    pub fn onboard_user(
        e: &Env,
        user: Address,
        operator: Address,
    ) -> Result<(), TestSacAdminError> {
        require_role(e, &operator, &DataKey::Onboarder)?;
        extend_instance_ttl(e);

        if is_on_block_list(e, &user) {
            return Err(TestSacAdminError::UserBlockedError);
        }

        let first_onboarding = !is_onboarded(e, &user);
        if first_onboarding {
            set_persistent_entry(e, &DataKey::Onboarded(user.clone()));
        }

        let sac = read_instance_address(e, &DataKey::SacToken);
        token::StellarAssetClient::new(e, &sac).set_authorized(&user, &true);

        if first_onboarding {
            UserOnboarded { user }.publish(e);
        }
        Ok(())
    }

    /// Places an address on the compliance block list and revokes SAC access.
    ///
    /// Calling this for an already block-listed address is a silent no-op.
    pub fn block_user(e: &Env, user: Address, operator: Address) -> Result<(), TestSacAdminError> {
        require_role(e, &operator, &DataKey::BlockOperator)?;
        extend_instance_ttl(e);

        if is_on_block_list(e, &user) {
            return Ok(());
        }

        set_persistent_entry(e, &DataKey::BlockListed(user.clone()));
        let sac = read_instance_address(e, &DataKey::SacToken);
        token::StellarAssetClient::new(e, &sac).set_authorized(&user, &false);
        UserBlocked { user }.publish(e);
        Ok(())
    }

    /// Removes an address from the compliance block list.
    ///
    /// SAC access is restored only if the address was previously onboarded.
    /// Calling this for an address not on the block list is a silent no-op.
    pub fn unblock_user(
        e: &Env,
        user: Address,
        operator: Address,
    ) -> Result<(), TestSacAdminError> {
        require_role(e, &operator, &DataKey::UnblockOperator)?;
        extend_instance_ttl(e);

        let block_key = DataKey::BlockListed(user.clone());
        if !persistent_entry_exists(e, &block_key) {
            return Ok(());
        }

        e.storage().persistent().remove(&block_key);
        if is_onboarded(e, &user) {
            let sac = read_instance_address(e, &DataKey::SacToken);
            token::StellarAssetClient::new(e, &sac).set_authorized(&user, &true);
        }
        UserUnblocked { user }.publish(e);
        Ok(())
    }

    /// Mints test tokens to an onboarded and currently authorized destination.
    ///
    /// # Errors
    ///
    /// Returns [`TestSacAdminError::InvalidAmount`] for non-positive amounts and
    /// [`TestSacAdminError::DestinationNotAuthorized`] when the destination
    /// cannot currently receive the SAC.
    pub fn mint(
        e: &Env,
        caller: Address,
        to: Address,
        amount: i128,
    ) -> Result<(), TestSacAdminError> {
        require_role(e, &caller, &DataKey::Minter)?;
        extend_instance_ttl(e);

        if amount <= 0 {
            return Err(TestSacAdminError::InvalidAmount);
        }
        if !is_onboarded(e, &to) || is_on_block_list(e, &to) || !sac_is_authorized(e, &to) {
            return Err(TestSacAdminError::DestinationNotAuthorized);
        }

        let sac = read_instance_address(e, &DataKey::SacToken);
        token::StellarAssetClient::new(e, &sac).mint(&to, &amount);
        Ok(())
    }

    /// Returns whether the address has ever been onboarded.
    pub fn is_onboarded(e: &Env, account: Address) -> bool {
        extend_instance_ttl(e);
        is_onboarded(e, &account)
    }

    /// Returns whether the address holds the fixed onboarder role.
    pub fn is_onboarder(e: &Env, account: Address) -> bool {
        extend_instance_ttl(e);
        account == read_instance_address(e, &DataKey::Onboarder)
    }

    /// Returns whether the address holds the fixed block-operator role.
    pub fn is_block_operator(e: &Env, account: Address) -> bool {
        extend_instance_ttl(e);
        account == read_instance_address(e, &DataKey::BlockOperator)
    }

    /// Returns whether the address holds the fixed unblock-operator role.
    pub fn is_unblock_operator(e: &Env, account: Address) -> bool {
        extend_instance_ttl(e);
        account == read_instance_address(e, &DataKey::UnblockOperator)
    }

    /// Returns whether the address is currently on the compliance block list.
    pub fn is_on_block_list(e: &Env, account: Address) -> bool {
        extend_instance_ttl(e);
        is_on_block_list(e, &account)
    }

    /// Returns the inverse of current SAC authorization.
    ///
    /// Missing trustlines and failed authorization queries are treated as
    /// blocked, independently of the contract-level block list.
    pub fn blocked(e: &Env, account: Address) -> bool {
        extend_instance_ttl(e);
        !sac_is_authorized(e, &account)
    }

    /// Returns the canonical SAC balance for an address.
    pub fn balance(e: &Env, account: Address) -> i128 {
        extend_instance_ttl(e);
        let sac = read_instance_address(e, &DataKey::SacToken);
        token::TokenClient::new(e, &sac).balance(&account)
    }

    /// Returns the administered SAC contract address.
    pub fn sac_token(e: &Env) -> Address {
        extend_instance_ttl(e);
        read_instance_address(e, &DataKey::SacToken)
    }
}

#[cfg(test)]
mod test {
    extern crate std;

    use soroban_sdk::{
        testutils::{storage::Persistent as _, Address as _, Events as _, IssuerFlags},
        token::{StellarAssetClient, TokenClient},
        Address, Env, Event, Val,
    };

    use super::*;

    struct Setup {
        env: Env,
        contract: TestSacAdminContractClient<'static>,
        sac: TokenClient<'static>,
        sac_admin: StellarAssetClient<'static>,
        minter: Address,
        onboarder: Address,
        blocker: Address,
        unblocker: Address,
    }

    fn setup() -> Setup {
        let env = Env::default();
        env.mock_all_auths();

        let issuer_admin = Address::generate(&env);
        let minter = Address::generate(&env);
        let onboarder = Address::generate(&env);
        let blocker = Address::generate(&env);
        let unblocker = Address::generate(&env);

        let registered_sac = env.register_stellar_asset_contract_v2(issuer_admin);
        let issuer = registered_sac.issuer();
        issuer.set_flag(IssuerFlags::RequiredFlag);
        issuer.set_flag(IssuerFlags::RevocableFlag);
        issuer.set_flag(IssuerFlags::ClawbackEnabledFlag);

        let sac_address = registered_sac.address();
        let contract_address = env.register(
            TestSacAdminContract,
            (&sac_address, &minter, &onboarder, &blocker, &unblocker),
        );
        let contract = TestSacAdminContractClient::new(&env, &contract_address);
        let sac = TokenClient::new(&env, &sac_address);
        let sac_admin = StellarAssetClient::new(&env, &sac_address);
        sac_admin.set_admin(&contract_address);

        Setup {
            env,
            contract,
            sac,
            sac_admin,
            minter,
            onboarder,
            blocker,
            unblocker,
        }
    }

    fn wrapper_events(s: &Setup) -> std::vec::Vec<(Address, soroban_sdk::Vec<Val>, Val)> {
        s.env
            .events()
            .all()
            .iter()
            .filter(|(address, _, _)| address == &s.contract.address)
            .collect()
    }

    fn assert_last_event<E: Event>(s: &Setup, expected: &E) {
        let events = wrapper_events(s);
        let (_, topics, _) = events.last().expect("expected wrapper event");
        assert_eq!(topics, &expected.topics(&s.env));
    }

    #[test]
    fn fresh_user_is_not_onboarded_or_block_list_but_is_sac_blocked() {
        let s = setup();
        let user = Address::generate(&s.env);

        assert!(!s.contract.is_onboarded(&user));
        assert!(!s.contract.is_on_block_list(&user));
        assert!(s.contract.blocked(&user));
    }

    #[test]
    fn first_onboarding_records_history_authorizes_and_emits() {
        let s = setup();
        let user = Address::generate(&s.env);

        s.contract.onboard_user(&user, &s.onboarder);

        assert_last_event(&s, &UserOnboarded { user: user.clone() });
        assert!(s.contract.is_onboarded(&user));
        assert!(!s.contract.blocked(&user));
    }

    #[test]
    fn repeated_onboarding_reauthorizes_without_duplicate_event() {
        let s = setup();
        let user = Address::generate(&s.env);
        s.contract.onboard_user(&user, &s.onboarder);
        s.sac_admin.set_authorized(&user, &false);
        let event_count = wrapper_events(&s).len();

        s.contract.onboard_user(&user, &s.onboarder);

        assert!(!s.contract.blocked(&user));
        assert_eq!(wrapper_events(&s).len(), event_count);
    }

    #[test]
    fn block_before_onboarding_then_unblock_does_not_authorize() {
        let s = setup();
        let user = Address::generate(&s.env);

        s.contract.block_user(&user, &s.blocker);
        s.contract.unblock_user(&user, &s.unblocker);

        assert!(!s.contract.is_onboarded(&user));
        assert!(!s.contract.is_on_block_list(&user));
        assert!(s.contract.blocked(&user));
    }

    #[test]
    fn onboarding_after_pre_onboarding_block_cycle_then_blocking_preserves_invariants() {
        let s = setup();
        let user = Address::generate(&s.env);
        s.contract.block_user(&user, &s.blocker);
        s.contract.unblock_user(&user, &s.unblocker);

        s.contract.onboard_user(&user, &s.onboarder);
        s.contract.block_user(&user, &s.blocker);

        assert!(s.contract.is_onboarded(&user));
        assert!(s.contract.is_on_block_list(&user));
        assert!(s.contract.blocked(&user));
    }

    #[test]
    fn onboarding_blocking_and_unblocking_restores_authorization() {
        let s = setup();
        let user = Address::generate(&s.env);
        s.contract.onboard_user(&user, &s.onboarder);

        s.contract.block_user(&user, &s.blocker);
        assert!(s.contract.is_onboarded(&user));
        assert!(s.contract.is_on_block_list(&user));
        assert!(s.contract.blocked(&user));

        s.contract.unblock_user(&user, &s.unblocker);
        assert!(s.contract.is_onboarded(&user));
        assert!(!s.contract.is_on_block_list(&user));
        assert!(!s.contract.blocked(&user));
    }

    #[test]
    fn onboarding_block_listed_user_returns_typed_error() {
        let s = setup();
        let user = Address::generate(&s.env);
        s.contract.block_user(&user, &s.blocker);

        let result = s.contract.try_onboard_user(&user, &s.onboarder);

        assert_eq!(result, Err(Ok(TestSacAdminError::UserBlockedError)));
        assert!(!s.contract.is_onboarded(&user));
        assert!(s.contract.is_on_block_list(&user));
    }

    #[test]
    fn blocked_onboarding_error_matches_gateway_compatibility_code() {
        assert_eq!(TestSacAdminError::UserBlockedError as u32, 105);
    }

    #[test]
    fn repeated_block_is_silent_noop() {
        let s = setup();
        let user = Address::generate(&s.env);
        s.contract.block_user(&user, &s.blocker);

        s.contract.block_user(&user, &s.blocker);

        assert!(wrapper_events(&s).is_empty());
    }

    #[test]
    fn unblock_when_not_block_listed_is_silent_noop() {
        let s = setup();
        let user = Address::generate(&s.env);
        let event_count = wrapper_events(&s).len();

        s.contract.unblock_user(&user, &s.unblocker);

        assert_eq!(wrapper_events(&s).len(), event_count);
    }

    #[test]
    fn block_and_unblock_emit_transition_events() {
        let s = setup();
        let user = Address::generate(&s.env);
        s.contract.onboard_user(&user, &s.onboarder);

        s.contract.block_user(&user, &s.blocker);
        assert_last_event(&s, &UserBlocked { user: user.clone() });

        s.contract.unblock_user(&user, &s.unblocker);
        assert_last_event(&s, &UserUnblocked { user });
    }

    #[test]
    fn transfer_succeeds_only_when_sender_and_recipient_are_authorized() {
        let s = setup();
        let sender = Address::generate(&s.env);
        let recipient = Address::generate(&s.env);
        s.contract.onboard_user(&sender, &s.onboarder);
        s.contract.onboard_user(&recipient, &s.onboarder);
        s.contract.mint(&s.minter, &sender, &1_000);

        s.sac.transfer(&sender, &recipient, &400);

        assert_eq!(s.contract.balance(&recipient), 400);
    }

    #[test]
    fn blocked_sender_cannot_transfer_until_unblocked() {
        let s = setup();
        let sender = Address::generate(&s.env);
        let recipient = Address::generate(&s.env);
        s.contract.onboard_user(&sender, &s.onboarder);
        s.contract.onboard_user(&recipient, &s.onboarder);
        s.contract.mint(&s.minter, &sender, &1_000);
        s.contract.block_user(&sender, &s.blocker);

        assert!(s.sac.try_transfer(&sender, &recipient, &400).is_err());

        s.contract.unblock_user(&sender, &s.unblocker);
        s.sac.transfer(&sender, &recipient, &400);
        assert_eq!(s.contract.balance(&recipient), 400);
    }

    #[test]
    fn unauthorized_recipient_cannot_receive_transfer() {
        let s = setup();
        let sender = Address::generate(&s.env);
        let recipient = Address::generate(&s.env);
        s.contract.onboard_user(&sender, &s.onboarder);
        s.contract.mint(&s.minter, &sender, &1_000);

        assert!(s.sac.try_transfer(&sender, &recipient, &400).is_err());
        assert_eq!(s.contract.balance(&recipient), 0);
    }

    #[test]
    fn mint_rejects_non_positive_amount_and_unauthorized_destination() {
        let s = setup();
        let onboarded = Address::generate(&s.env);
        let unauthorized = Address::generate(&s.env);
        s.contract.onboard_user(&onboarded, &s.onboarder);

        assert_eq!(
            s.contract.try_mint(&s.minter, &onboarded, &0),
            Err(Ok(TestSacAdminError::InvalidAmount))
        );
        assert_eq!(
            s.contract.try_mint(&s.minter, &unauthorized, &1),
            Err(Ok(TestSacAdminError::DestinationNotAuthorized))
        );
    }

    #[test]
    fn mint_rejects_onboarded_but_block_listed_destination() {
        let s = setup();
        let user = Address::generate(&s.env);
        s.contract.onboard_user(&user, &s.onboarder);
        s.contract.block_user(&user, &s.blocker);

        let result = s.contract.try_mint(&s.minter, &user, &1);

        assert_eq!(result, Err(Ok(TestSacAdminError::DestinationNotAuthorized)));
        assert_eq!(s.contract.balance(&user), 0);
    }

    #[test]
    fn wrong_role_cannot_perform_other_operator_action() {
        let s = setup();
        let user = Address::generate(&s.env);

        assert_eq!(
            s.contract.try_onboard_user(&user, &s.blocker),
            Err(Ok(TestSacAdminError::Unauthorized))
        );
        assert_eq!(
            s.contract.try_block_user(&user, &s.onboarder),
            Err(Ok(TestSacAdminError::Unauthorized))
        );
        assert_eq!(
            s.contract.try_unblock_user(&user, &s.blocker),
            Err(Ok(TestSacAdminError::Unauthorized))
        );
    }

    #[test]
    fn one_wallet_can_hold_every_operator_role() {
        let env = Env::default();
        env.mock_all_auths();
        let wallet = Address::generate(&env);
        let registered_sac = env.register_stellar_asset_contract_v2(wallet.clone());
        let issuer = registered_sac.issuer();
        issuer.set_flag(IssuerFlags::RequiredFlag);
        issuer.set_flag(IssuerFlags::RevocableFlag);
        issuer.set_flag(IssuerFlags::ClawbackEnabledFlag);
        let sac_address = registered_sac.address();
        let contract_address = env.register(
            TestSacAdminContract,
            (&sac_address, &wallet, &wallet, &wallet, &wallet),
        );
        StellarAssetClient::new(&env, &sac_address).set_admin(&contract_address);
        let contract = TestSacAdminContractClient::new(&env, &contract_address);
        let user = Address::generate(&env);

        contract.onboard_user(&user, &wallet);
        contract.mint(&wallet, &user, &100);
        contract.block_user(&user, &wallet);
        contract.unblock_user(&user, &wallet);

        assert!(!contract.blocked(&user));
        assert_eq!(contract.balance(&user), 100);
    }

    #[test]
    fn operator_signature_is_required() {
        let s = setup();
        s.env.mock_auths(&[]);
        let user = Address::generate(&s.env);

        assert!(s.contract.try_onboard_user(&user, &s.onboarder).is_err());
        assert!(s.contract.try_block_user(&user, &s.blocker).is_err());
        assert!(s.contract.try_unblock_user(&user, &s.unblocker).is_err());
    }

    #[test]
    fn is_onboarder_identifies_only_the_configured_onboarder() {
        let s = setup();

        assert!(s.contract.is_onboarder(&s.onboarder));
        assert!(!s.contract.is_onboarder(&s.blocker));
    }

    #[test]
    fn operator_views_identify_only_their_configured_roles() {
        let s = setup();

        assert!(s.contract.is_block_operator(&s.blocker));
        assert!(!s.contract.is_block_operator(&s.unblocker));
        assert!(s.contract.is_unblock_operator(&s.unblocker));
        assert!(!s.contract.is_unblock_operator(&s.blocker));
    }

    #[test]
    fn persistent_state_is_extended_for_long_lived_tests() {
        let s = setup();
        let user = Address::generate(&s.env);
        s.contract.onboard_user(&user, &s.onboarder);

        let ttl = s.env.as_contract(&s.contract.address, || {
            s.env
                .storage()
                .persistent()
                .get_ttl(&DataKey::Onboarded(user))
        });

        assert!(ttl >= PERSISTENT_LIFETIME_THRESHOLD);
    }
}
