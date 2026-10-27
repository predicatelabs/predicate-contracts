# Asset Compliance Examples

Example token contracts with compliance controls built in: freeze, seize, and role-gated admin. Once you grant Predicate the freeze role, it can freeze accounts automatically based on your policy.

## How it works

1. Your token implements a supported freeze interface gated by role-based access control. The examples here implement [`IFreezable`](../../interfaces/IFreezable.sol), which is supported.
2. You grant only the freeze role to Predicate's enforcement address.
3. Predicate watches the data sources in your policy (e.g. OFAC sanctions) and calls `freeze` on your contract automatically. You can also freeze manually from the dashboard.

Predicate's enforcement address: `0x363c256D368277BBFaf6EaF65beE123a7AdbA464`

### Wallet onboarding

A token can also restrict who may hold it to an allowlist that Predicate manages. Once a wallet passes your onboarding policy, Predicate adds it to the list; when it should lose access, Predicate removes it. There is no step for the wallet holder: an EVM wallet is onboarded by a single allowlist write from Predicate's enforcement address.

[`OnboardableToken.sol`](OnboardableToken.sol) shows this alongside freezing. Mints and transfers revert with `AddressNotAllowed` unless every non-zero party is on the list, and freeze checks still apply on top.

## Role model

The roles a token defines, and who holds them, are the issuer's choice. The pattern below is the one the example token implements and the one we recommend: role-based access control where no single key can both freeze an account and move or destroy its funds. Each capability is its own role held by a separate key, and `DEFAULT_ADMIN_ROLE` (ideally a multisig or timelock) administers the others and authorizes upgrades.

Nothing forces this separation. A token could define a single role and grant it to Predicate, but that is not adequate — it would let the freeze key also mint, seize, or upgrade. Implemented as below, Predicate holds only `FREEZE_MANAGER_ROLE`; you keep admin, seize, and mint.

| Capability | Role | Holder |
| --- | --- | --- |
| Freeze / unfreeze (+ batch) | `FREEZE_MANAGER_ROLE` | Predicate enforcer, and/or issuer ops |
| Onboard / offboard wallets (`OnboardableToken`) | `WHITELIST_MANAGER_ROLE` | Predicate enforcer |
| Seize / clawback | `FORCED_TRANSFER_MANAGER_ROLE` | Issuer, separate key from freeze |
| Pause | `PAUSER_ROLE` | Issuer ops |
| Mint / burn | `MINTER_ROLE` / `BURNER_ROLE` | Issuer treasury |
| Admin / upgrade / roles | `DEFAULT_ADMIN_ROLE` | Issuer multisig or timelock |

### The freeze manager role

`FREEZE_MANAGER_ROLE` is the only role you grant Predicate.

- It authorizes `freeze`, `unfreeze`, and their batch variants, and nothing else. In the example provided, freezing is reversible and moves no funds.

### The whitelist manager role

`WHITELIST_MANAGER_ROLE` is the role you grant Predicate for wallet onboarding.

- It authorizes `addToWhitelist` and `revokeFromWhitelist`, and nothing else. It cannot freeze, mint, or move funds.
- A caller without it reverts with `OnlyWhitelistManager(address)`. Predicate reads that error to confirm it holds the role when you enroll, so keep it if you adapt the example.

## Examples

| File | What it shows |
| --- | --- |
| [`FreezableStablecoin.sol`](FreezableStablecoin.sol) | Upgradeable ERC-20 on the [`Freezable`](../../Freezable.sol) base (implements `IFreezable`), with EIP-2612 permit, pause, role-gated mint/burn, and seize (`forceTransfer`). Freeze is enforced in `_update`, blocking both send and receive. |
| [`FreezableToken.sol`](FreezableToken.sol) | The smallest token that implements `IFreezable`: the bare interface, no extras. |
| [`OnboardableToken.sol`](OnboardableToken.sol) | ERC-20 on the [`Freezable`](../../Freezable.sol) base that also implements the wallet onboarding interface. Mints and transfers require every non-zero party to be onboarded; burns do not. |
| [`Freezable.sol`](../../Freezable.sol) · [`IFreezable.sol`](../../interfaces/IFreezable.sol) | The reusable freeze base and its interface. |
| [`DeployFreezableStablecoin.s.sol`](../../../script/asset-compliance/DeployFreezableStablecoin.s.sol) | Deploys the token behind an ERC-1967 proxy with initial roles. |
| [`GrantFreezeManager.s.sol`](../../../script/asset-compliance/GrantFreezeManager.s.sol) | Grant (`run()`), revoke (`revoke()`), and verify (`check()`) Predicate's `FREEZE_MANAGER_ROLE`, with `cast` equivalents. |
| [`FreezableStablecoin.t.sol`](../../../test/asset-compliance/FreezableStablecoin.t.sol) | Tests covering freeze enforcement, the role boundaries (the freeze role cannot seize/mint/pause/upgrade), and that revoking the role disables enforcement. |
| [`DeployOnboardableToken.s.sol`](../../../script/asset-compliance/DeployOnboardableToken.s.sol) | Deploys `OnboardableToken`, granting both `FREEZE_MANAGER_ROLE` and `WHITELIST_MANAGER_ROLE` to Predicate's enforcement address by default. |
| [`OnboardableToken.t.sol`](../../../test/asset-compliance/OnboardableToken.t.sol) | Tests covering the onboarding interface and its errors, allowlist enforcement on mint and transfer, and how it combines with freezing. |

```bash
forge test --match-path "*asset-compliance*"
```

## Supported interfaces

Predicate calls a fixed freeze interface; it does not adapt to a token's own method or role names. To be enforceable, your token must implement one of the supported interfaces.

[`IFreezable`](../../interfaces/IFreezable.sol), which the examples here implement, is supported. If you don't have a freeze interface yet, start from [`FreezableStablecoin.sol`](FreezableStablecoin.sol).

If your token already uses a different freeze or blocklist interface, reach out to us to confirm whether it's supported before enrolling.

For wallet onboarding, Predicate calls this allowlist interface, which [`OnboardableToken.sol`](OnboardableToken.sol) implements:

| Function / error | Purpose |
| --- | --- |
| `isAllowed(address) returns (bool)` | Whether a wallet is onboarded. Must return `false` for any address that was never added. |
| `addToWhitelist(address[])` | Onboard wallets. Gated by the whitelist manager role. |
| `revokeFromWhitelist(address[])` | Offboard wallets. Gated by the whitelist manager role. |
| `version() returns (string)` | Contract version. |
| `error OnlyWhitelistManager(address)` | Raised when the caller lacks the whitelist manager role. |
| `error AddressNotAllowed(address)` | Raised when a wallet that is not onboarded is refused. |

## Further reading

- [Compliance for Assets — overview](https://docs.predicate.io/v2/assets/overview)
- [Enroll your asset](https://docs.predicate.io/v2/assets/get-started)
- [Security model](https://docs.predicate.io/v2/assets/security)
