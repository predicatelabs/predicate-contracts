# Asset Compliance Examples

Example token contracts that enforce compliance onchain — freeze, seize, and role-gated admin — and that Predicate can drive automatically.

Code: [`src/examples/asset-compliance/`](../src/examples/asset-compliance/).

## How it works

1. Your token exposes a freeze interface gated by role-based access control — the [`IFreezable`](../src/interfaces/IFreezable.sol) interface.
2. You grant only the freeze role to Predicate's enforcement address.
3. Predicate watches the data sources in your policy (e.g. OFAC sanctions) and calls `freeze` on your contract automatically. You can also freeze manually from the dashboard. You run no infrastructure, and Predicate never holds your admin keys.

Predicate's enforcement address (grant it `FREEZE_MANAGER_ROLE`): `0x363c256D368277BBFaf6EaF65beE123a7AdbA464`

## Role model

The roles a token defines, and who holds them, are the issuer's choice. The pattern below is the one the example token implements: role-based access control where no single key can both freeze an account and move or destroy its funds. Each capability is its own role held by a separate key, and `DEFAULT_ADMIN_ROLE` (ideally a multisig or timelock) administers the others and authorizes upgrades.

| Capability | Role | Holder |
| --- | --- | --- |
| Freeze / unfreeze (+ batch) | `FREEZE_MANAGER_ROLE` | Predicate enforcer, and/or issuer ops |
| Seize / clawback | `FORCED_TRANSFER_MANAGER_ROLE` | Issuer, separate key from freeze |
| Pause | `PAUSER_ROLE` | Issuer ops |
| Mint / burn | `MINTER_ROLE` / `BURNER_ROLE` | Issuer treasury |
| Admin / upgrade / roles | `DEFAULT_ADMIN_ROLE` | Issuer multisig or timelock |

### The freeze manager role

`FREEZE_MANAGER_ROLE` is the only role you grant Predicate.

- It authorizes `freeze`, `unfreeze`, and their batch variants, and nothing else: it cannot mint, burn, seize, pause, upgrade, or administer roles. Freezing is reversible and moves no funds, though it does stop the account from sending and receiving. The example token enforces this boundary, and the [tests](../test/asset-compliance/FreezableStablecoin.t.sol) check it.
- Keep it separate from seize. Freezing and seizing are different powers: a freeze flags an account, and a distinct issuer-held role decides whether to claw the balance back. If your token combines both in one role, split them before granting, so the freeze key can never move or destroy funds.
- Hold the role yourself, delegate it to Predicate, or both. Granting and revoking it is a single `AccessControl` call — see [`GrantFreezeManager.s.sol`](../script/asset-compliance/GrantFreezeManager.s.sol).

## Examples

| File | What it shows |
| --- | --- |
| [`FreezableStablecoin.sol`](../src/examples/asset-compliance/FreezableStablecoin.sol) | Upgradeable ERC-20 on the [`Freezable`](../src/Freezable.sol) base (implements `IFreezable`), with EIP-2612 permit, pause, role-gated mint/burn, and seize (`forceTransfer`). Freeze is enforced in `_update`, blocking both send and receive. |
| [`FreezableToken.sol`](../src/examples/asset-compliance/FreezableToken.sol) | The smallest token that implements `IFreezable`: the bare interface, no extras. |
| [`Freezable.sol`](../src/Freezable.sol) · [`IFreezable.sol`](../src/interfaces/IFreezable.sol) | The reusable freeze base and its interface. |
| [`DeployFreezableStablecoin.s.sol`](../script/asset-compliance/DeployFreezableStablecoin.s.sol) | Deploys the token behind an ERC-1967 proxy with initial roles. |
| [`GrantFreezeManager.s.sol`](../script/asset-compliance/GrantFreezeManager.s.sol) | Grant (`run()`), revoke (`revoke()`), and verify (`check()`) Predicate's `FREEZE_MANAGER_ROLE`, with `cast` equivalents. |
| [`FreezableStablecoin.t.sol`](../test/asset-compliance/FreezableStablecoin.t.sol) | Tests covering freeze enforcement, the role boundaries (the freeze role cannot seize/mint/pause/upgrade), and that revoking the role disables enforcement. |

```bash
forge test --match-path "*asset-compliance*"
```

## Driving an existing token

You don't have to deploy a new token — Predicate can drive a token's existing freeze or blocklist interface. Common shapes:

| Interface shape | What it takes |
| --- | --- |
| `freeze` / `unfreeze` (+ batch) gated by a freeze role (`IFreezable`-style) | Grant the freeze role. `FreezableStablecoin` is this shape. |
| Freeze plus a forced-burn governed by the same role | Split the burn out of that role first, so the freeze key can't destroy funds, then grant it. An adapter maps the method and role names if they differ. |
| Blocklist (`blacklist` / `isBlacklisted`) gated by a blocklister role | Grant the blocklister role; an adapter maps the names. |
| Standalone blocklist contract (`addToBlocklist` / `isBlocked`) | Grant write access; prefer a role over a single `Ownable` owner. |

No freeze interface yet? Start from [`FreezableStablecoin.sol`](../src/examples/asset-compliance/FreezableStablecoin.sol).

## Further reading

- [Compliance for Assets — overview](https://docs.predicate.io/v2/assets/overview)
- [Enroll your asset](https://docs.predicate.io/v2/assets/get-started)
- [Security model](https://docs.predicate.io/v2/assets/security)
