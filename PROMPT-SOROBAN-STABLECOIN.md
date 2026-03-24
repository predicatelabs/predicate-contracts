# Prompt: Add Soroban Stablecoin Contract to predicate-contracts

## Context

This repository (`predicate-contracts`) contains Predicate's compliance smart contract framework. It currently has **EVM/Solidity contracts only**, built with Foundry. The core contracts are:

- **PredicateRegistry** — Central registry managing attesters, policies, and attestation validation
- **PredicateClient** — Abstract mixin that other contracts inherit to integrate Predicate compliance
- **BasicPredicateClient** — Simplified client for sender-only validation
- **MetaCoin** — Example contract demonstrating integration

Contracts are published to Contrafactory (an artifact registry) via CI/CD, and consumed by a separate dashboard app (contractor-app) for deployment.

We need to add a **Soroban (Stellar) stablecoin contract** with freezable/compliance capabilities, plus the Soroban equivalent of the PredicateRegistry and PredicateClient.

## PRD Requirements

From the Stellar Support PRD:

- **Track 1 (Asset Compliance):** A Soroban token contract with freeze support, analogous to EVM's `IFreezable`. OpenZeppelin's Stellar contracts provide audited freeze, allowlist/blocklist, and RBAC extensions.
- **Track 2 (Application Compliance):** A Soroban PredicateRegistry contract — registration of attesters, policy binding, Ed25519 attestation validation.

**Deadline:** April 1, 2026
**Key reference:** [OpenZeppelin Stellar Contracts](https://developers.stellar.org/docs/tools/openzeppelin-contracts)

## What To Build

### 1. Directory Structure

Create a `soroban/` directory at the repository root for all Soroban contracts. Each contract should be its own Rust crate:

```
soroban/
├── Cargo.toml                      # Workspace manifest
├── predicate-registry/
│   ├── Cargo.toml
│   └── src/
│       └── lib.rs                  # Soroban PredicateRegistry contract
├── test-stablecoin/
│   ├── Cargo.toml
│   └── src/
│       └── lib.rs                  # Freezable stablecoin (SAC-compatible)
├── predicate-client/
│   ├── Cargo.toml
│   └── src/
│       └── lib.rs                  # PredicateClient trait/library for integration
└── README.md                       # Soroban contracts documentation
```

### 2. Test Stablecoin Contract (`soroban/test-stablecoin/`)

A Soroban token contract (SAC-compatible) with compliance features:

**Token functionality:**
- Standard Soroban token interface: `initialize`, `mint`, `transfer`, `burn`, `balance`, `decimals`, `name`, `symbol`
- Admin-controlled minting
- 6 decimals (standard for stablecoins on Stellar)

**Compliance/Freeze functionality (Asset Compliance — Track 1):**
- `freeze(address)` — Freeze an account (blocks transfers to/from)
- `unfreeze(address)` — Unfreeze an account
- `is_frozen(address) -> bool` — Check freeze status
- All transfers must check freeze status of both sender and recipient
- Only the designated compliance admin can freeze/unfreeze

**RBAC:**
- `admin` — Can mint, set compliance admin
- `compliance_admin` — Can freeze/unfreeze accounts (this will be Predicate's enforcement wallet)

**Reference:** Align with or use OpenZeppelin's Stellar contracts library for the freezable trait and RBAC. See: https://developers.stellar.org/docs/tools/openzeppelin-contracts

### 3. Predicate Registry Contract (`soroban/predicate-registry/`)

Port the core PredicateRegistry logic from `src/PredicateRegistry.sol` to Soroban. Key functionality:

**Attester management:**
- `register_attester(address)` — Owner-only, add a trusted attester
- `deregister_attester(address)` — Owner-only, remove an attester
- `get_registered_attesters() -> Vec<Address>` — List all attesters
- `is_attester_registered(address) -> bool` — Check registration

**Policy management:**
- `set_policy_id(client_address, policy_id: String)` — Set policy for a client contract
- `get_policy_id(client_address) -> String` — Get policy for a client

**Attestation validation:**
- `validate_attestation(statement, attestation) -> bool` — Core validation
- Verify Ed25519 signature (NOT ECDSA — Stellar uses Ed25519, same as Solana)
- UUID-based replay protection (mark UUIDs as spent)
- Expiration timestamp validation
- Attester registration check

**Data structures (adapt from Solidity):**

The EVM Statement struct:
```
uuid: String
msg_sender: Address
target: Address
msg_value: u128
encoded_sig_and_args: Bytes
policy: String
expiration: u64
```

The EVM Attestation struct:
```
uuid: String
expiration: u64
attester: Address
signature: BytesN<64>  (Ed25519 signature)
```

**Key differences from EVM version:**
- Use Ed25519 signature verification instead of ECDSA (Stellar native curve)
- Use Soroban's `env.crypto().ed25519_verify()` for signature checks
- Use Soroban persistent storage for attester registry and UUID tracking
- No proxy/upgrade pattern needed initially (Soroban contracts can be updated by the deployer)
- Use `Address` type for Stellar addresses (handles both G... accounts and C... contracts)

### 4. Predicate Client Library (`soroban/predicate-client/`)

A Rust library crate (not a standalone contract) that other Soroban contracts can import to integrate Predicate compliance. Equivalent of `src/mixins/PredicateClient.sol`.

**Provides:**
- `authorize_transaction(env, registry_address, attestation, encoded_args, sender)` — Constructs a Statement, calls the registry's `validate_attestation`
- Helper functions for building statements
- Types for Statement and Attestation

### 5. Tests

Each contract should have comprehensive tests using `soroban-sdk`'s test utilities:

**test-stablecoin tests:**
- Mint, transfer, burn basics
- Freeze blocks transfers (both sender and recipient)
- Unfreeze restores transfers
- Only compliance admin can freeze/unfreeze
- Only admin can mint

**predicate-registry tests:**
- Register/deregister attesters
- Policy set/get
- Valid attestation accepted
- Expired attestation rejected
- Replayed UUID rejected
- Unregistered attester rejected
- Invalid Ed25519 signature rejected

### 6. Build & CI Configuration

**Cargo workspace** (`soroban/Cargo.toml`):
```toml
[workspace]
members = [
    "predicate-registry",
    "test-stablecoin",
    "predicate-client",
]

[workspace.dependencies]
soroban-sdk = "22.0.0"  # Use latest stable
soroban-token-sdk = "22.0.0"
```

**Each contract's Cargo.toml** should include:
```toml
[lib]
crate-type = ["cdylib"]

[dependencies]
soroban-sdk = { workspace = true }

[dev-dependencies]
soroban-sdk = { workspace = true, features = ["testutils"] }
```

**Update `.github/workflows/contracts.yml`** to also build and test Soroban contracts:
```yaml
- name: Build Soroban contracts
  run: |
    cd soroban
    soroban contract build

- name: Test Soroban contracts
  run: |
    cd soroban
    cargo test
```

**Update `contrafactory.toml`** or create a Soroban-specific publish config so that the compiled WASM and contract specs get published to Contrafactory under the `predicate-contracts` project.

### 7. Contrafactory Publishing

The compiled WASM artifacts need to be published to Contrafactory so the contractor-app can fetch them. Update `.github/workflows/publish.yml` to:

1. Build Soroban contracts: `soroban contract build`
2. The compiled WASM files will be in `soroban/target/wasm32-unknown-unknown/release/`
3. Publish each contract's WASM and spec to Contrafactory under:
   - Package: `stellar-test-stablecoin` → artifacts: `/wasm`, `/spec`
   - Package: `stellar-predicate-registry` → artifacts: `/wasm`, `/spec`

The exact Contrafactory CLI commands for Soroban artifacts need to be coordinated with the Contrafactory team — the API needs new endpoints for `/wasm` and `/spec` artifact types.

## Key Technical References

**Stellar/Soroban docs:**
- [Soroban overview](https://developers.stellar.org/docs/build/smart-contracts/overview)
- [Soroban token contracts (SAC)](https://developers.stellar.org/docs/tokens/stellar-asset-contract)
- [Authorization](https://developers.stellar.org/docs/learn/fundamentals/contract-development/authorization)
- [OpenZeppelin Stellar Contracts](https://developers.stellar.org/docs/tools/openzeppelin-contracts)

**Existing EVM contracts to reference (in this repo):**
- `src/PredicateRegistry.sol` — Core registry logic to port
- `src/mixins/PredicateClient.sol` — Client mixin to port
- `src/interfaces/IPredicateRegistry.sol` — Statement/Attestation struct definitions
- `test/PredicateRegistryAttestation.t.sol` — Test patterns to replicate

**Ed25519 on Soroban:**
- Soroban provides native Ed25519 verification via `env.crypto().ed25519_verify(public_key, message, signature)`
- This is the same curve Solana uses — the existing Solana attestation infrastructure can sign for Stellar too

## Out of Scope

- Classic Stellar asset freezing (`SetTrustLineFlags`) — Soroban contracts only
- Proxy/upgrade patterns — Soroban deployer can update contracts directly
- Advanced PredicateClient patterns (proxy pattern, wrapper pattern) — start with direct inheritance
- Frontend/dashboard changes — handled separately in contractor-app
