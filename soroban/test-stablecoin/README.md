# Test SAC Admin Contract

> TEST ONLY. This contract is unaudited, intentionally incomplete, and not
> production-ready. Do not use it to administer assets of value.

This package is a small Soroban integration harness for testing a private
Stellar asset. It administers a Stellar Asset Contract (SAC) whose issuer has
`AUTH_REQUIRED`, `AUTH_REVOCABLE`, and `AUTH_CLAWBACK_ENABLED` set.

It is an independent test implementation built against Stellar's public SAC
interfaces. It is not affiliated with, endorsed by, or a production substitute
for M0, MoneyGram, MGUSD, or their contracts.

## State model

The contract intentionally keeps three related states:

- `is_onboarded(address)` is permanent onboarding history.
- `is_on_block_list(address)` is the current compliance hold.
- `blocked(address)` is the inverse of the SAC's current authorization flag.

These states can differ. In particular:

- A fresh trustline is not onboarded, not block-listed, and SAC-blocked.
- Blocking before onboarding and then unblocking clears the hold but does not
  authorize the address.
- Onboarding, blocking, and then unblocking restores authorization because the
  onboarding record persists.
- Deleting and recreating a trustline resets SAC authorization. Calling
  `onboard_user` again reauthorizes it without emitting a second onboarding
  event.

## Public test API

- `onboard_user(user, operator)`
- `block_user(user, operator)`
- `unblock_user(user, operator)`
- `mint(caller, to, amount)`
- `is_onboarded(account)`
- `is_on_block_list(account)`
- `blocked(account)`
- `balance(account)`
- `sac_token()`

The onboarder, block operator, unblock operator, and minter are fixed at
deployment. One wallet may hold every role.

Transfers are made directly through the SAC. This wrapper intentionally does
not proxy the SEP-41 transfer interface.

## Deliberate omissions

The contract has no batch operations, role rotation, burn endpoint, forced
transfer, pause, upgrade, yield, supply accounting, or issuer-renunciation
logic. Those omissions keep the artifact focused on onboarding and compliance
state permutations.

## Deployment

Use `../scripts/deploy.sh`. The script:

1. Sets the required issuer flags.
2. Deploys the SAC for the configured classic asset.
3. Builds and deploys this wrapper.
4. Transfers SAC administration to the wrapper.

The script defaults all identities and roles to one wallet. Mainnet execution
requires an explicit `ALLOW_MAINNET_TEST_DEPLOY=I_UNDERSTAND_TEST_ONLY`
acknowledgement.

## License

This package is part of the Predicate contracts repository and is distributed
under the repository's MIT license. Functional behavior was independently
implemented from public Stellar interfaces. Similarity in behavior to another
system does not establish legal clearance; consult counsel if licensing risk is
material to deployment or distribution.
