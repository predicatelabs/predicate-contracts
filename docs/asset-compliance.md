# Asset Compliance Examples

Example token contracts with compliance controls built in: freeze, seize, and role-gated admin. Once you grant Predicate the freeze role, it can freeze accounts automatically based on your policy.

Code: [`src/examples/asset-compliance/`](../src/examples/asset-compliance/).

## How it works

1. Your token implements a supported freeze interface gated by role-based access control. The examples here implement [`IFreezable`](../src/interfaces/IFreezable.sol), which is supported.
2. You grant only the freeze role to Predicate's enforcement address.
3. Predicate watches the data sources in your policy (e.g. OFAC sanctions) and calls `freeze` on your contract automatically. You can also freeze manually from the dashboard. 

Predicate's enforcement address: `0x363c256D368277BBFaf6EaF65beE123a7AdbA464`

## Role model

The roles a token defines, and who holds them, are the issuer's choice. The pattern below is the one the example token implements and the one we recommend: role-based access control where no single key can both freeze an account and move or destroy its funds. Each capability is its own role held by a separate key, and `DEFAULT_ADMIN_ROLE` (ideally a multisig or timelock) administers the others and authorizes upgrades.

Nothing forces this separation. A token could define a single role and grant it to Predicate, but that is not adequate — it would let the freeze key also mint, seize, or upgrade. Implemented as below, Predicate holds only `FREEZE_MANAGER_ROLE`; you keep admin, seize, and mint.

| Capability | Role | Holder |
| --- | --- | --- |
| Freeze / unfreeze (+ batch) | `FREEZE_MANAGER_ROLE` | Predicate enforcer, and/or issuer ops |
| Seize / clawback | `FORCED_TRANSFER_MANAGER_ROLE` | Issuer, separate key from freeze |
| Pause | `PAUSER_ROLE` | Issuer ops |
| Mint / burn | `MINTER_ROLE` / `BURNER_ROLE` | Issuer treasury |
| Admin / upgrade / roles | `DEFAULT_ADMIN_ROLE` | Issuer multisig or timelock |

### The freeze manager role

`FREEZE_MANAGER_ROLE` is the only role you grant Predicate.

- It authorizes `freeze`, `unfreeze`, and their batch variants, and nothing else. In the example provided, freezing is reversible and moves no funds.

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

## Supported interfaces

Predicate calls a fixed freeze interface; it does not adapt to a token's own method or role names. To be enforceable, your token must implement one of the supported interfaces.

[`IFreezable`](../src/interfaces/IFreezable.sol), which the examples here implement, is supported. If you don't have a freeze interface yet, start from [`FreezableStablecoin.sol`](../src/examples/asset-compliance/FreezableStablecoin.sol).

If your token already uses a different freeze or blocklist interface, reach out to us to confirm whether it's supported before enrolling.

## Further reading

- [Compliance for Assets — overview](https://docs.predicate.io/v2/assets/overview)
- [Enroll your asset](https://docs.predicate.io/v2/assets/get-started)
- [Security model](https://docs.predicate.io/v2/assets/security)
