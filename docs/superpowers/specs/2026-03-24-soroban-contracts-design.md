# Soroban Contracts for Predicate — Design Spec

**Date:** 2026-03-24
**Status:** Approved
**Deadline:** April 1, 2026

## Overview

Add Soroban (Stellar) smart contracts to the predicate-contracts repository: a freezable test stablecoin, a PredicateRegistry port, and a PredicateClient library. These contracts bring Predicate's compliance framework to the Stellar ecosystem.

## Approach

From-scratch implementation using `soroban-sdk 25.3.0` and `soroban-token-sdk 25.3.0`. No OpenZeppelin Stellar library — the freeze/RBAC logic is straightforward and keeping it self-contained avoids a new dependency on a young library. The stablecoin is a pure Soroban contract (not wrapping a Classic asset), giving full control over freeze logic without Classic trustline complexity.

## Directory Structure

```
soroban/
├── Cargo.toml                      # Workspace manifest
├── predicate-client/
│   ├── Cargo.toml                  # rlib (not deployed)
│   └── src/
│       └── lib.rs
├── predicate-registry/
│   ├── Cargo.toml                  # cdylib (deployed contract)
│   └── src/
│       └── lib.rs
├── test-stablecoin/
│   ├── Cargo.toml                  # cdylib (deployed contract)
│   └── src/
│       └── lib.rs
└── README.md
```

## Crate Dependency Graph

```
test-stablecoin ──→ predicate-client (types only)
predicate-registry ──→ predicate-client (types + helpers)
```

`predicate-client` is a library crate (`rlib`), not a deployed contract. It provides shared types and the `authorize_transaction` helper that other contracts import.

## Data Structures

### Statement

Adapted from the EVM `Statement` struct in `IPredicateRegistry.sol`:

```rust
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Statement {
    pub uuid: String,
    pub msg_sender: Address,
    pub target: Address,
    pub msg_value: i128,
    pub encoded_sig_and_args: Bytes,
    pub policy: String,
    pub expiration: u64,
}
```

### Attestation

Adapted from the EVM `Attestation` struct. Key difference: `attester` is a `BytesN<32>` (Ed25519 public key) instead of an EVM `address`, since Ed25519 verification operates on raw public keys.

```rust
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Attestation {
    pub uuid: String,
    pub expiration: u64,
    pub attester: BytesN<32>,
    pub signature: BytesN<64>,
}
```

## Contract 1: predicate-client (Library)

**Purpose:** Shared types and helper functions for Predicate compliance integration. Equivalent of `src/mixins/PredicateClient.sol`.

**Exports:**
- `Statement` and `Attestation` types (above)
- `authorize_transaction(env, registry_address, attestation, encoded_args, sender, value)` — constructs a `Statement`, calls the registry's `validate_attestation` via cross-contract invocation
- Helper for serializing a `Statement` into signable bytes

**Not a contract** — no `#[contract]` attribute, no WASM output. Just a Rust library other Soroban contracts depend on.

## Contract 2: predicate-registry

**Purpose:** Port of `PredicateRegistry.sol`. Central on-chain registry managing attesters, policies, and Ed25519 attestation validation.

### Storage Layout

| Key | Storage Type | Value |
|-----|-------------|-------|
| `owner` | Instance | `Address` |
| `attester:{pubkey}` | Persistent | `bool` |
| `attester_index:{pubkey}` | Persistent | `u32` |
| `attesters_list` | Persistent | `Vec<BytesN<32>>` |
| `policy:{client_addr}` | Persistent | `String` |
| `uuid:{uuid_string}` | Persistent | `bool` |

Instance storage for owner (lives with contract instance). Persistent storage for attesters, policies, and spent UUIDs (survives archival with TTL extension). The `attester_index` mapping enables O(1) swap-and-pop deregistration, mirroring the EVM contract's `attesterIndex`.

### Functions

**Initialization:**
- `initialize(env, owner: Address)` — Set contract owner. Panics if already initialized.

**Ownership:**
- `set_owner(env, new_owner: Address)` — Owner-only. Transfer ownership to a new address.

**Attester Management (owner-only):**
- `register_attester(env, attester: BytesN<32>)` — Add a trusted attester public key. Panics if already registered.
- `deregister_attester(env, attester: BytesN<32>)` — Remove an attester. Swap-and-pop for O(1) removal.
- `get_registered_attesters(env) -> Vec<BytesN<32>>` — List all registered attester public keys.
- `is_attester_registered(env, attester: BytesN<32>) -> bool` — Check registration status.

**Policy Management:**
- `set_policy_id(env, client: Address, policy_id: String)` — Client sets its own policy. Requires `client.require_auth()`.
- `get_policy_id(env, client: Address) -> String` — Get policy for a client contract.

**Attestation Validation:**
- `validate_attestation(env, statement: Statement, attestation: Attestation)` — Core validation. Panics on any failure; success is implicit (see flow below).
- `hash_statement(env, statement: Statement) -> BytesN<32>` — Public function returning the message hash for a given statement. Used by off-chain attesters to compute what to sign.

### Validation Flow

All failure paths panic with descriptive error messages. The function returns `()` — success is implicit (reaching the end without panic).

```
validate_attestation(statement, attestation):
  1. Check attestation.expiration > env.ledger().timestamp()  — panic if expired
  2. Check statement.uuid == attestation.uuid  — panic if mismatch
  3. Check statement.expiration == attestation.expiration  — panic if mismatch
  4. Check uuid not in spent UUIDs  — panic if replayed
  5. Check attester is registered  — panic if not (fail fast before crypto)
  6. Serialize statement into message bytes (deterministic encoding)
  7. env.crypto().ed25519_verify(&attester_pubkey, &message, &signature)
     — Panics on invalid signature (Soroban native behavior)
  8. Mark uuid as spent in persistent storage
  9. Emit event: (statement details, attester)
```

### Cross-Contract Replay Protection

The EVM version uses `msg.sender` substitution in `hashStatementSafe`. The Soroban equivalent:

- The `target` field in `Statement` is set to the **calling contract's address**
- The calling contract passes its own address and calls `require_auth` on it before invoking validation
- This binds the attestation to a specific client contract, preventing reuse across contracts

### Signature Message Format

The message signed by attesters is a deterministic serialization of:
```
(uuid, msg_sender, target, msg_value, encoded_sig_and_args, policy, expiration)
```

Prepend `env.ledger().network_id()` (the SHA-256 hash of the network passphrase, `BytesN<32>`) to the serialized statement fields before signing. Off-chain attesters must use the same network passphrase hash when constructing the message to sign. Fields are concatenated using Soroban's `Bytes` with length-prefixed variable-length fields to avoid ambiguity.

## Contract 3: test-stablecoin

**Purpose:** SAC-compatible token with freeze/compliance support. Demonstrates Track 1 (Asset Compliance) for Stellar.

### Storage Layout

| Key | Storage Type | Value |
|-----|-------------|-------|
| `admin` | Instance | `Address` |
| `compliance_admin` | Instance | `Address` |
| `name` | Instance | `String` |
| `symbol` | Instance | `String` |
| `decimals` | Instance | `u32` (always 6) |
| `balance:{addr}` | Persistent | `i128` |
| `allowance:{from}:{spender}` | Temporary | `AllowanceData { amount: i128, expiration_ledger: u32 }` |
| `frozen:{addr}` | Persistent | `bool` |

### RBAC

Two roles:

**admin** (set at initialization):
- `mint(to, amount)` — Create new tokens
- `set_compliance_admin(new_admin)` — Designate the compliance admin
- `set_admin(new_admin)` — Transfer admin role

**compliance_admin** (set by admin):
- `freeze(account)` — Block all transfers to/from account
- `unfreeze(account)` — Restore transfer ability
- This will be Predicate's enforcement wallet in production

### Token Interface (SAC-compatible)

**Initialization:**
- `initialize(env, admin: Address, decimal: u32, name: String, symbol: String)` — Set up the token. Panics if already initialized.

**Standard Token Functions:**
- `mint(env, to: Address, amount: i128)` — Admin-only. Mint to any address.
- `transfer(env, from: Address, to: Address, amount: i128)` — Requires `from.require_auth()`. Checks freeze on both `from` and `to`.
- `transfer_from(env, spender: Address, from: Address, to: Address, amount: i128)` — Allowance-based transfer. Checks freeze on both `from` and `to`.
- `approve(env, from: Address, spender: Address, amount: i128, expiration_ledger: u32)` — Set spending allowance.
- `burn(env, from: Address, amount: i128)` — Requires `from.require_auth()`. Burns tokens.
- `burn_from(env, spender: Address, from: Address, amount: i128)` — Allowance-based burn.
- `balance(env, id: Address) -> i128` — Get balance.
- `allowance(env, from: Address, spender: Address) -> i128` — Get allowance.
- `decimals(env) -> u32` — Returns 6.
- `name(env) -> String` — Token name.
- `symbol(env) -> String` — Token symbol.

**Compliance Functions:**
- `freeze(env, account: Address)` — Compliance admin only. Sets frozen flag.
- `unfreeze(env, account: Address)` — Compliance admin only. Clears frozen flag.
- `is_frozen(env, account: Address) -> bool` — Public query.
- `set_compliance_admin(env, new_admin: Address)` — Admin only.

**Freeze enforcement:** `transfer`, `transfer_from`, `burn`, and `burn_from` all panic if the source account is frozen. This prevents frozen accounts from reducing their balance during compliance investigations. `mint` is not affected by freeze — the admin can still mint to frozen accounts. Transfers to frozen recipients are also blocked.

### Events

Standard Soroban token events plus:
- `freeze(admin: Address, account: Address)`
- `unfreeze(admin: Address, account: Address)`
- `set_compliance_admin(admin: Address, new_compliance_admin: Address)`

## Testing Strategy

All tests use `soroban-sdk` testutils with `#[cfg(test)]` modules.

### predicate-registry tests

| Test | Description |
|------|-------------|
| `test_initialize` | Owner is set correctly |
| `test_register_attester` | Attester added, appears in list |
| `test_register_attester_not_owner` | Non-owner cannot register (panics) |
| `test_deregister_attester` | Attester removed, no longer in list |
| `test_deregister_attester_not_registered` | Deregistering unknown attester panics |
| `test_set_get_policy` | Client sets and retrieves policy |
| `test_valid_attestation` | Full happy path — valid signature accepted |
| `test_expired_attestation` | Expired attestation rejected |
| `test_replayed_uuid` | Same UUID used twice rejected |
| `test_unregistered_attester` | Valid signature from unregistered attester rejected |
| `test_invalid_signature` | Tampered signature rejected |
| `test_uuid_mismatch` | Statement/attestation UUID mismatch rejected |
| `test_expiration_mismatch` | Statement/attestation expiration mismatch rejected |
| `test_set_policy_not_authorized` | Cannot set policy for another address |
| `test_double_initialize` | Calling initialize twice panics |
| `test_set_owner` | Owner can transfer ownership |
| `test_set_owner_not_owner` | Non-owner cannot transfer ownership |

### test-stablecoin tests

| Test | Description |
|------|-------------|
| `test_initialize` | Name, symbol, decimals set correctly |
| `test_mint` | Admin mints, balance increases |
| `test_mint_not_admin` | Non-admin cannot mint (panics) |
| `test_transfer` | Basic transfer between accounts |
| `test_transfer_insufficient` | Transfer exceeding balance panics |
| `test_burn` | Burn reduces balance |
| `test_freeze_blocks_transfer_from` | Frozen sender cannot transfer |
| `test_freeze_blocks_transfer_to` | Cannot transfer to frozen recipient |
| `test_unfreeze_restores_transfer` | Unfrozen account can transfer again |
| `test_freeze_not_compliance_admin` | Non-compliance-admin cannot freeze (panics) |
| `test_set_compliance_admin` | Admin can change compliance admin |
| `test_set_compliance_admin_not_admin` | Non-admin cannot set compliance admin |
| `test_approve_and_transfer_from` | Allowance-based transfer works |
| `test_transfer_from_frozen` | Allowance transfer blocked when frozen |
| `test_mint_to_frozen` | Minting to frozen account succeeds |
| `test_burn_frozen_account` | Frozen account cannot burn (panics) |
| `test_double_initialize` | Calling initialize twice panics |

### predicate-client tests

| Test | Description |
|------|-------------|
| `test_statement_construction` | Helper builds correct Statement from inputs |
| `test_authorize_transaction_integration` | End-to-end: client lib → registry validation |

## TTL Management

Soroban persistent storage entries that are not extended will eventually become archived and inaccessible. Both contracts should extend TTLs on critical storage entries during write operations:

- **predicate-registry:** Extend attester entries and the attesters list when registering/deregistering. Extend UUID entries when marking them spent. Also provide an `extend_ttl(env)` admin function for bulk TTL extension of critical state.
- **test-stablecoin:** Extend balance entries on mint/transfer. Extend instance storage (admin, compliance_admin, metadata) via `env.storage().instance().extend_ttl()` on state-changing operations.

Operational TTL extension via `stellar contract extend` is also available as a fallback.

## CI/CD Updates

### contracts.yml additions

Add a job for Soroban contracts:
```yaml
soroban-build:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Install Rust
      uses: dtolnay/rust-toolchain@stable
      with:
        targets: wasm32-unknown-unknown
    - name: Install Stellar CLI
      run: cargo install stellar-cli
    - name: Build Soroban contracts
      run: cd soroban && stellar contract build
    - name: Test Soroban contracts
      run: cd soroban && cargo test
```

### publish.yml additions

After existing Foundry publish steps, add Soroban WASM publishing:
```yaml
- name: Build Soroban contracts
  run: cd soroban && stellar contract build
- name: Publish Soroban artifacts
  run: |
    # Publish test-stablecoin WASM
    contrafactory publish stellar-test-stablecoin \
      --artifact wasm:soroban/target/wasm32-unknown-unknown/release/test_stablecoin.wasm \
      --version ${{ env.VERSION }}
    # Publish predicate-registry WASM
    contrafactory publish stellar-predicate-registry \
      --artifact wasm:soroban/target/wasm32-unknown-unknown/release/predicate_registry.wasm \
      --version ${{ env.VERSION }}
```

Note: Exact Contrafactory CLI commands for WASM/spec artifact types need coordination with the Contrafactory team per the PRD.

## Out of Scope

- Classic Stellar asset freezing (`SetTrustLineFlags`)
- Proxy/upgrade patterns (Soroban deployer can update directly)
- Advanced PredicateClient patterns (proxy, wrapper)
- Frontend/dashboard changes (handled in contractor-app)
- Clawback functionality (admin forcibly moving tokens from frozen accounts) — freeze-only enforcement for now
- Production deployment configuration
