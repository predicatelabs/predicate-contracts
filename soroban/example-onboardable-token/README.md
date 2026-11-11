# Onboardable Token (Soroban)

The Stellar counterpart of the EVM
[`OnboardableToken`](../../src/examples/asset-compliance/OnboardableToken.sol):
a SEP-41 token that restricts who may hold it to an onboarding list that
Predicate manages, with a compliance block list on top.

Once a wallet passes your onboarding policy, Predicate calls `onboard_user`;
when it should lose access, `offboard_user`. There is no step for the wallet
holder. Predicate's enforcement address can also block and unblock accounts.

Predicate's Stellar enforcement address:
`GCDJXKIZODN7SISUQYLIP2PDIRAGASCGV7P62ABEJE7M7ISAZVHD6SFL`

Built on OpenZeppelin Stellar Contracts 0.6.0 (`stellar-tokens`,
`stellar-access`): balances, allowances, metadata, events, and role
management come from the library; this crate adds the gating and the
interface below.

## Behavior

- Mints require the recipient to be onboarded and not blocked.
- `transfer` and `transfer_from` require both the owner and the recipient to be
  onboarded and not blocked. The spender in `transfer_from` is not checked.
- `burn` and `burn_from` skip the onboarding check but still refuse a blocked
  owner, so a block holds funds in place.
- A blocked wallet cannot be onboarded: `onboard_user` refuses it with
  `UserBlockedError`. Blocking an onboarded wallet does not offboard it, so it
  can transact again once unblocked.
- Onboard, offboard, block, and unblock are idempotent; events are emitted only
  on a state change.

## Role model

Roles use OpenZeppelin `AccessControl`. The admin is set at deploy, can grant
and revoke every role (`grant_role`, `revoke_role`), and is the only address
that can mint. Each operator role authorizes its own functions and nothing
else; none of them can mint or move funds.

| Capability | Role | Holder |
| --- | --- | --- |
| Onboard / offboard wallets | `onboarder` | Predicate enforcer |
| Block | `blocker` | Predicate enforcer, and/or issuer ops |
| Unblock | `unblocker` | Predicate enforcer, and/or issuer ops |
| Mint / roles | admin | Issuer multisig |

## Interface

Predicate calls a fixed interface and does not adapt to a token's own function
names. Keep these names, argument order, and error codes if you adapt the
example.

| Function | Purpose |
| --- | --- |
| `onboard_user(user, operator)` | Onboard a wallet. `operator` must hold `onboarder` and sign. Refuses a blocked wallet with `UserBlockedError`. |
| `is_onboarded(account) -> bool` | Whether a wallet is onboarded. `false` for any address never onboarded. |
| `is_onboarder(account) -> bool` | Whether an address holds `onboarder`. |
| `block_user(user, operator)` | Block an account. `operator` must hold `blocker` and sign. |
| `unblock_user(user, operator)` | Unblock an account. `operator` must hold `unblocker` and sign. |
| `batch_block_users(users, operator)` | Block every account in `users`. Requires `blocker`. |
| `batch_unblock_users(users, operator)` | Unblock every account in `users`. Requires `unblocker`. |
| `is_on_block_list(account) -> bool` | Whether an account is blocked. |
| `is_block_operator(account) -> bool` | Whether an address holds `blocker`. |
| `is_unblock_operator(account) -> bool` | Whether an address holds `unblocker`. |
| `balance(account) -> i128` | SEP-41 balance. |

The token also implements these, which Predicate does not call today:

| Function | Purpose |
| --- | --- |
| `batch_onboard_users(users, operator) -> Vec<Address>` | Onboard every wallet in `users`. Requires `onboarder`. Blocked wallets are skipped and returned. |
| `offboard_user(user, operator)` | Offboard a wallet. Requires `onboarder`. |
| `batch_offboard_users(users, operator)` | Offboard every wallet in `users`. Requires `onboarder`. |

Each batch function checks the operator's role and signature once, then
applies the single-wallet logic to every entry, so already-applied entries and
duplicates are skipped without an event. A batch takes at most
`MAX_BATCH_SIZE` (40) wallets; a larger one is refused with
`BatchTooLargeError`. A refused batch writes nothing.

| Error | Code | Raised when |
| --- | --- | --- |
| `OnboardableTokenError::BatchTooLargeError` | 102 | A batch has more than 40 wallets. |
| `OnboardableTokenError::UserBlockedError` | 105 | `onboard_user` is called for a blocked wallet. |
| `FungibleTokenError::UserNotAllowed` | 113 | A party that must be onboarded is not. |
| `FungibleTokenError::UserBlocked` | 114 | A party is on the block list. |
| `AccessControlError::Unauthorized` | 2000 | `operator` lacks the role for the call. |

## Deployment

```bash
./scripts/deploy-onboardable-token.sh <identity> [admin] [onboarder] [block_operator] [unblock_operator]
```

The admin defaults to the identity's address and every operator role to
Predicate's enforcement address. Set `STELLAR_NETWORK` (default `testnet`),
`TOKEN_NAME`, and `TOKEN_SYMBOL` to override.

## Tests

```bash
cd soroban && cargo test -p example-onboardable-token
```
