# Asset Compliance Examples

Token contracts that enforce compliance on-chain — freeze, seize, and role-gated admin — and that Predicate can drive automatically.

Code: [`src/examples/asset-compliance/`](../src/examples/asset-compliance/).

## How it works

1. Your token exposes a freeze interface with role-based access control — the [`IFreezable`](../src/interfaces/IFreezable.sol) interface.
2. You grant only the freeze role to Predicate's enforcement address.
3. Predicate monitors the data sources in your policy (e.g. OFAC sanctions) and calls `freeze` on your contract automatically — you can also act manually from the dashboard. You run no infrastructure, and Predicate never holds your admin keys.

Predicate's enforcement address (grant it `FREEZE_MANAGER_ROLE`): `0x363c256D368277BBFaf6EaF65beE123a7AdbA464`

## Role separation

The role you grant Predicate authorizes freeze/unfreeze and nothing else. Mint, burn, seize/clawback, pause, upgrade, and role administration are separate roles you keep. The example token enforces this and tests it.

If your token bundles seize or burn into the same role as freeze — for example a single "asset protection" role that gates both `freeze` and a balance-wiping `wipeFrozenAddress` — split it before integrating, so the role Predicate holds can never move or destroy funds.

| Capability | Role | Granted to Predicate |
| --- | --- | :---: |
| Freeze / unfreeze (+ batch) | `FREEZE_MANAGER_ROLE` | yes — only this |
| Seize / clawback | `FORCED_TRANSFER_MANAGER_ROLE` | no |
| Pause | `PAUSER_ROLE` | no |
| Mint / burn | `MINTER_ROLE` / `BURNER_ROLE` | no |
| Admin / upgrade / roles | `DEFAULT_ADMIN_ROLE` | no |

## Examples

| File | What it shows |
| --- | --- |
| [`FreezableStablecoin.sol`](../src/examples/asset-compliance/FreezableStablecoin.sol) | Upgradeable ERC-20 on the M^0 [`Freezable`](../src/Freezable.sol) base (implements `IFreezable`), with EIP-2612 permit, pause, role-gated mint/burn, and seize (`forceTransfer`). Freeze is enforced in `_update` — blocks send and receive. |
| [`FreezableToken.sol`](../src/examples/asset-compliance/FreezableToken.sol) | The smallest token that implements `IFreezable`: the bare interface, no extras. |
| [`Freezable.sol`](../src/Freezable.sol) · [`IFreezable.sol`](../src/interfaces/IFreezable.sol) | The reusable freeze base and its interface. |
| [`DeployFreezableStablecoin.s.sol`](../script/asset-compliance/DeployFreezableStablecoin.s.sol) | Deploys the token behind an ERC-1967 proxy with initial roles. |
| [`GrantFreezeManager.s.sol`](../script/asset-compliance/GrantFreezeManager.s.sol) | Grant (`run()`), revoke (`revoke()`), and verify (`check()`) Predicate's `FREEZE_MANAGER_ROLE`. Includes `cast` equivalents. |
| [`FreezableStablecoin.t.sol`](../test/asset-compliance/FreezableStablecoin.t.sol) | Tests, including proofs that the freeze role cannot seize/mint/pause/upgrade and that revocation disables enforcement. |

```bash
forge test --match-path "*asset-compliance*"
```

## Does your existing token already work?

Predicate drives your token's existing freeze/blocklist interface; most regulated tokens already have one.

| Token shape | Example | Fit | What it takes |
| --- | --- | --- | --- |
| M^0 `IFreezable` (`freeze`/`unfreeze`/`freezeAccounts` + `FREEZE_MANAGER_ROLE`) | mUSD, USDR | Native | Grant `FREEZE_MANAGER_ROLE`. `FreezableStablecoin` is this shape. |
| Paxos `PaxosTokenV2` (`freeze`/`freezeBatch`/`wipeFrozenAddress` + `ASSET_PROTECTION_ROLE`) | USDG | Compatible | Grant the role, but split off `wipeFrozenAddress` first — that one role also burns (see role separation). Method/role names differ from `IFreezable`, so it uses a dedicated enforcement adapter. |
| Circle FiatToken-style blocklist (`blacklist`/`isBlacklisted` + `blacklister`) | USDC family | Compatible | Grant the blacklister role; dedicated adapter. |
| Standalone blocklist contract (`addToBlocklist`/`isBlocked`) | Ondo `Blocklist` | Drivable | Grant write access; prefer a role-scoped owner over a single `Ownable` owner. |

No freeze interface yet? Start from [`FreezableStablecoin.sol`](../src/examples/asset-compliance/FreezableStablecoin.sol).

## Further reading

- [Compliance for Assets — overview](https://docs.predicate.io/v2/assets/overview)
- [Enroll your asset](https://docs.predicate.io/v2/assets/get-started)
- [Security model](https://docs.predicate.io/v2/assets/security)
