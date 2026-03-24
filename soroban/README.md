# Soroban Contracts

Predicate compliance contracts for the Stellar/Soroban ecosystem.

## Contracts

- **predicate-registry** -- Attester management, policy binding, Ed25519 attestation validation. Port of the EVM `PredicateRegistry.sol`.
- **test-stablecoin** -- SAC-compatible token with freeze/compliance support and RBAC (admin + compliance admin).
- **predicate-client** -- Shared types (`Statement`, `Attestation`) and helpers (`authorize_transaction`, `serialize_statement`) for Predicate integration. Library crate, not deployed.

## Build

```bash
stellar contract build
```

Requires `stellar-cli` and the `wasm32-unknown-unknown` Rust target:

```bash
cargo install stellar-cli --locked
rustup target add wasm32-unknown-unknown
```

## Test

```bash
cargo test
```

## Architecture

See `docs/superpowers/specs/2026-03-24-soroban-contracts-design.md` for the full design spec.
