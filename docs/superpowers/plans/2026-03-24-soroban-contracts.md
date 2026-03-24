# Soroban Contracts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Soroban (Stellar) smart contracts to predicate-contracts: a predicate-client library, predicate-registry contract, and test-stablecoin contract with freeze/compliance support.

**Architecture:** Three Rust crates in a Cargo workspace under `soroban/`. `predicate-client` is a shared library (rlib) exporting types and helpers. `predicate-registry` and `test-stablecoin` are deployable contracts (cdylib) that depend on `predicate-client`. All contracts use `soroban-sdk 25.3.0`.

**Tech Stack:** Rust, soroban-sdk 25.3.0, soroban-token-sdk 25.3.0, Ed25519 signatures, Soroban persistent/instance/temporary storage.

**Spec:** `docs/superpowers/specs/2026-03-24-soroban-contracts-design.md`

---

## File Map

| File | Responsibility |
|------|---------------|
| `soroban/Cargo.toml` | Workspace manifest with shared dependency versions |
| `soroban/predicate-client/Cargo.toml` | Library crate config (rlib, no cdylib) |
| `soroban/predicate-client/src/lib.rs` | Statement, Attestation types + authorize_transaction helper + serialize_statement |
| `soroban/predicate-registry/Cargo.toml` | Contract crate config (cdylib) |
| `soroban/predicate-registry/src/lib.rs` | Registry contract: attester mgmt, policy mgmt, Ed25519 attestation validation |
| `soroban/test-stablecoin/Cargo.toml` | Contract crate config (cdylib) |
| `soroban/test-stablecoin/src/lib.rs` | SAC-compatible token with freeze, RBAC, compliance functions |
| `soroban/README.md` | Overview of Soroban contracts |
| `.github/workflows/contracts.yml` | Add soroban-build-test job |
| `.github/workflows/publish.yml` | Add Soroban WASM publishing steps |

---

## Task 1: Workspace Scaffolding

**Files:**
- Create: `soroban/Cargo.toml`
- Create: `soroban/predicate-client/Cargo.toml`
- Create: `soroban/predicate-client/src/lib.rs` (minimal placeholder)
- Create: `soroban/predicate-registry/Cargo.toml`
- Create: `soroban/predicate-registry/src/lib.rs` (minimal placeholder)
- Create: `soroban/test-stablecoin/Cargo.toml`
- Create: `soroban/test-stablecoin/src/lib.rs` (minimal placeholder)

- [ ] **Step 1: Create workspace Cargo.toml**

```toml
# soroban/Cargo.toml
[workspace]
resolver = "2"
members = [
    "predicate-client",
    "predicate-registry",
    "test-stablecoin",
]

[workspace.dependencies]
soroban-sdk = "25.3.0"
soroban-token-sdk = "25.3.0"
predicate-client = { path = "predicate-client" }
ed25519-dalek = { version = "2", features = ["rand_core"] }
```

- [ ] **Step 2: Create predicate-client Cargo.toml**

```toml
# soroban/predicate-client/Cargo.toml
[package]
name = "predicate-client"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["rlib"]

[dependencies]
soroban-sdk = { workspace = true }

[dev-dependencies]
soroban-sdk = { workspace = true, features = ["testutils"] }
ed25519-dalek = { workspace = true }
```

- [ ] **Step 3: Create predicate-registry Cargo.toml**

```toml
# soroban/predicate-registry/Cargo.toml
[package]
name = "predicate-registry"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
soroban-sdk = { workspace = true }
predicate-client = { workspace = true }

[dev-dependencies]
soroban-sdk = { workspace = true, features = ["testutils"] }
predicate-client = { workspace = true }
ed25519-dalek = { workspace = true }
```

- [ ] **Step 4: Create test-stablecoin Cargo.toml**

```toml
# soroban/test-stablecoin/Cargo.toml
[package]
name = "test-stablecoin"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
soroban-sdk = { workspace = true }
soroban-token-sdk = { workspace = true }

[dev-dependencies]
soroban-sdk = { workspace = true, features = ["testutils"] }
```

- [ ] **Step 5: Create minimal placeholder lib.rs files**

Each `lib.rs` should contain just `#![no_std]` and the soroban-sdk import to verify compilation:

```rust
// soroban/predicate-client/src/lib.rs
#![no_std]
use soroban_sdk::{contracttype, Address, Bytes, BytesN, Env, String};
```

```rust
// soroban/predicate-registry/src/lib.rs
#![no_std]
use soroban_sdk::{contract, contractimpl, Env};

#[contract]
pub struct PredicateRegistryContract;

#[contractimpl]
impl PredicateRegistryContract {}
```

```rust
// soroban/test-stablecoin/src/lib.rs
#![no_std]
use soroban_sdk::{contract, contractimpl, Env};

#[contract]
pub struct TestStablecoinContract;

#[contractimpl]
impl TestStablecoinContract {}
```

- [ ] **Step 6: Verify workspace compiles**

Run: `cd soroban && cargo check`
Expected: Compiles with no errors (warnings are OK).

- [ ] **Step 7: Commit**

```bash
git add soroban/
git commit -m "feat(soroban): scaffold workspace with three crates"
```

---

## Task 2: predicate-client — Types and Helpers

**Files:**
- Modify: `soroban/predicate-client/src/lib.rs`

- [ ] **Step 1: Write test for Statement and Attestation types**

Add to `soroban/predicate-client/src/lib.rs`:

```rust
#[cfg(test)]
mod test {
    use super::*;
    use soroban_sdk::Env;

    #[test]
    fn test_statement_construction() {
        let env = Env::default();
        let statement = Statement {
            uuid: String::from_str(&env, "test-uuid"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 1000u64,
        };
        assert_eq!(statement.uuid, String::from_str(&env, "test-uuid"));
        assert_eq!(statement.expiration, 1000u64);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd soroban && cargo test -p predicate-client`
Expected: FAIL — `Statement` not defined yet.

- [ ] **Step 3: Implement Statement and Attestation types**

In `soroban/predicate-client/src/lib.rs`:

```rust
#![no_std]
use soroban_sdk::{contracttype, Address, Bytes, BytesN, Env, String};

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

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Attestation {
    pub uuid: String,
    pub expiration: u64,
    pub attester: BytesN<32>,
    pub signature: BytesN<64>,
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd soroban && cargo test -p predicate-client`
Expected: PASS

- [ ] **Step 5: Add serialize_statement helper**

This function serializes a Statement into deterministic bytes for Ed25519 signing. The approach: convert the Statement to its Soroban XDR representation (which `#[contracttype]` provides via `IntoVal`/`TryFromVal`), then prepend the network ID. Off-chain attesters must produce the same byte sequence.

**Wire format:** `network_id (32 bytes) || statement_xdr_bytes (variable)`

The `#[contracttype]` derive generates XDR serialization automatically. We use `soroban_sdk::ToXdr` to get deterministic bytes.

```rust
use soroban_sdk::IntoVal;

/// Serialize a Statement into bytes for Ed25519 signing.
/// Wire format: network_id (32 bytes) || statement XDR (variable length).
/// Off-chain attesters must produce identical bytes using Stellar XDR libs.
pub fn serialize_statement(env: &Env, statement: &Statement) -> Bytes {
    // Convert statement to XDR bytes via Soroban's contracttype serialization
    let statement_val = statement.clone().into_val(env);
    let statement_xdr = env.to_xdr(statement_val);

    // Prepend network ID (SHA-256 of network passphrase, 32 bytes)
    let network_id = env.ledger().network_id();
    let mut message = Bytes::from_slice(env, &network_id.to_array());
    message.append(&statement_xdr);
    message
}
```

**Important:** `env.to_xdr()` is available in soroban-sdk 25.x via the `Env` trait. If `to_xdr` is not available as a method, use:
```rust
use soroban_sdk::xdr::{ToXdr, WriteXdr};
let xdr_bytes = statement.to_xdr(env);
```
The implementer should verify which XDR serialization API is available in 25.3.0 and use the working one. The key contract is: **network_id ++ XDR-serialized statement**. Attesters sign these raw bytes directly (no hashing before signing — Ed25519 handles its own internal hashing).

- [ ] **Step 6: Add authorize_transaction helper**

```rust
/// Constructs a Statement and calls the registry's validate_attestation via cross-contract call.
/// Panics if validation fails.
pub fn authorize_transaction(
    env: &Env,
    registry_address: &Address,
    attestation: &Attestation,
    encoded_sig_and_args: &Bytes,
    msg_sender: &Address,
    msg_value: i128,
    policy: &String,
) {
    let statement = Statement {
        uuid: attestation.uuid.clone(),
        msg_sender: msg_sender.clone(),
        target: env.current_contract_address(),
        msg_value,
        encoded_sig_and_args: encoded_sig_and_args.clone(),
        policy: policy.clone(),
        expiration: attestation.expiration,
    };

    // Cross-contract call to registry
    let registry_client = crate::PredicateRegistryClient::new(env, registry_address);
    registry_client.validate_attestation(&statement, attestation);
}
```

Note: The `PredicateRegistryClient` type is auto-generated when the predicate-registry contract is compiled. Since predicate-client is a library that doesn't depend on predicate-registry (to avoid circular deps), `authorize_transaction` should be generic — accept a registry address and make the cross-contract call using `env.invoke_contract()` directly.

Note on `env.current_contract_address()`: Even though this is a library function (rlib), when called from a contract context, `env.current_contract_address()` returns the calling contract's address. This is the correct behavior — it binds the attestation to the specific client contract calling this helper.

```rust
use soroban_sdk::{vec, IntoVal, Symbol, Val};

pub fn authorize_transaction(
    env: &Env,
    registry_address: &Address,
    attestation: &Attestation,
    encoded_sig_and_args: &Bytes,
    msg_sender: &Address,
    msg_value: i128,
    policy: &String,
) {
    let statement = Statement {
        uuid: attestation.uuid.clone(),
        msg_sender: msg_sender.clone(),
        target: env.current_contract_address(),
        msg_value,
        encoded_sig_and_args: encoded_sig_and_args.clone(),
        policy: policy.clone(),
        expiration: attestation.expiration,
    };

    let args: Vec<Val> = vec![
        &env,
        statement.into_val(env),
        attestation.clone().into_val(env),
    ];
    env.invoke_contract::<()>(
        registry_address,
        &Symbol::new(env, "validate_attestation"),
        args,
    );
}
```

- [ ] **Step 7: Run tests**

Run: `cd soroban && cargo test -p predicate-client`
Expected: PASS (the authorize_transaction integration test will be added in Task 5 after the registry is implemented)

- [ ] **Step 8: Commit**

```bash
git add soroban/predicate-client/
git commit -m "feat(soroban): implement predicate-client types and helpers"
```

---

## Task 3: predicate-registry — Core Contract

**Files:**
- Modify: `soroban/predicate-registry/src/lib.rs`

This is the largest task. It implements the full PredicateRegistry port.

### Step Group A: Storage Keys and Initialization

- [ ] **Step 1: Write test for initialize**

```rust
#[cfg(test)]
mod test {
    use super::*;
    use soroban_sdk::testutils::Address as _;
    use soroban_sdk::Env;

    fn setup_registry(env: &Env) -> (Address, PredicateRegistryContractClient) {
        let contract_id = env.register(PredicateRegistryContract, ());
        let client = PredicateRegistryContractClient::new(env, &contract_id);
        let owner = Address::generate(env);
        client.initialize(&owner);
        (owner, client)
    }

    #[test]
    fn test_initialize() {
        let env = Env::default();
        let (owner, client) = setup_registry(&env);
        // Should not panic — means initialized successfully
        // Verify by calling a function that requires initialization
        let attesters = client.get_registered_attesters();
        assert_eq!(attesters.len(), 0);
    }

    #[test]
    #[should_panic(expected = "already initialized")]
    fn test_double_initialize() {
        let env = Env::default();
        let (owner, client) = setup_registry(&env);
        let other = Address::generate(&env);
        client.initialize(&other);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd soroban && cargo test -p predicate-registry`
Expected: FAIL — functions not implemented.

- [ ] **Step 3: Implement storage keys and initialize**

```rust
#![no_std]
use predicate_client::{Attestation, Statement};
use soroban_sdk::{
    contract, contractimpl, contracttype,
    Address, Bytes, BytesN, Env, String, Symbol, Vec,
};

const LEDGER_BUMP_AMOUNT: u32 = 518_400; // ~30 days
const LEDGER_THRESHOLD: u32 = 432_000;   // ~25 days

#[contracttype]
#[derive(Clone)]
enum DataKey {
    Owner,
    Initialized,
    Attester(BytesN<32>),
    AttesterIndex(BytesN<32>),
    AttestersList,
    Policy(Address),
    UsedUuid(String),
}

#[contract]
pub struct PredicateRegistryContract;

#[contractimpl]
impl PredicateRegistryContract {
    pub fn initialize(env: Env, owner: Address) {
        if env.storage().instance().has(&DataKey::Initialized) {
            panic!("already initialized");
        }
        env.storage().instance().set(&DataKey::Initialized, &true);
        env.storage().instance().set(&DataKey::Owner, &owner);
        env.storage().persistent().set(&DataKey::AttestersList, &Vec::<BytesN<32>>::new(&env));
        env.storage().instance().extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);
    }

    // ... (continued in subsequent steps)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd soroban && cargo test -p predicate-registry`
Expected: PASS for initialize tests.

### Step Group B: Ownership

- [ ] **Step 5: Write ownership tests**

```rust
    #[test]
    fn test_set_owner() {
        let env = Env::default();
        env.mock_all_auths();
        let (owner, client) = setup_registry(&env);
        let new_owner = Address::generate(&env);
        client.set_owner(&new_owner);
        // Verify new owner can register an attester
        let attester = BytesN::from_array(&env, &[1u8; 32]);
        client.register_attester(&attester);
    }

    #[test]
    #[should_panic]
    fn test_set_owner_not_owner() {
        let env = Env::default();
        let (owner, client) = setup_registry(&env);
        // Don't mock auths — should fail
        let new_owner = Address::generate(&env);
        client.set_owner(&new_owner);
    }
```

- [ ] **Step 6: Implement set_owner and require_owner helper**

```rust
    fn require_owner(env: &Env) {
        let owner: Address = env.storage().instance().get(&DataKey::Owner).unwrap();
        owner.require_auth();
    }

    pub fn set_owner(env: Env, new_owner: Address) {
        Self::require_owner(&env);
        env.storage().instance().set(&DataKey::Owner, &new_owner);
        env.storage().instance().extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);
    }
```

- [ ] **Step 7: Run tests**

Run: `cd soroban && cargo test -p predicate-registry`
Expected: PASS

### Step Group C: Attester Management

- [ ] **Step 8: Write attester management tests**

```rust
    #[test]
    fn test_register_attester() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        let attester = BytesN::from_array(&env, &[1u8; 32]);
        client.register_attester(&attester);
        assert!(client.is_attester_registered(&attester));
        let attesters = client.get_registered_attesters();
        assert_eq!(attesters.len(), 1);
        // Note: In soroban-sdk 25.x, Vec::get() may return T directly (panics on OOB)
        // or Option<T>. Check the SDK docs and adjust — remove .unwrap() if not needed.
        assert_eq!(attesters.get(0).unwrap(), attester);
    }

    #[test]
    #[should_panic]
    fn test_register_attester_not_owner() {
        let env = Env::default();
        // Don't mock auths
        let (_owner, client) = setup_registry(&env);
        let attester = BytesN::from_array(&env, &[1u8; 32]);
        client.register_attester(&attester);
    }

    #[test]
    fn test_deregister_attester() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        let attester1 = BytesN::from_array(&env, &[1u8; 32]);
        let attester2 = BytesN::from_array(&env, &[2u8; 32]);
        client.register_attester(&attester1);
        client.register_attester(&attester2);
        assert_eq!(client.get_registered_attesters().len(), 2);

        client.deregister_attester(&attester1);
        assert!(!client.is_attester_registered(&attester1));
        assert!(client.is_attester_registered(&attester2));
        assert_eq!(client.get_registered_attesters().len(), 1);
    }

    #[test]
    #[should_panic(expected = "attester not registered")]
    fn test_deregister_attester_not_registered() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        let attester = BytesN::from_array(&env, &[1u8; 32]);
        client.deregister_attester(&attester);
    }
```

- [ ] **Step 9: Implement attester management functions**

```rust
    pub fn register_attester(env: Env, attester: BytesN<32>) {
        Self::require_owner(&env);
        let key = DataKey::Attester(attester.clone());
        if env.storage().persistent().has(&key) && env.storage().persistent().get::<_, bool>(&key).unwrap() {
            panic!("attester already registered");
        }
        // Get current list and append
        let mut attesters: Vec<BytesN<32>> = env.storage().persistent()
            .get(&DataKey::AttestersList).unwrap_or(Vec::new(&env));
        let index = attesters.len();
        attesters.push_back(attester.clone());

        env.storage().persistent().set(&DataKey::AttestersList, &attesters);
        env.storage().persistent().set(&key, &true);
        env.storage().persistent().set(&DataKey::AttesterIndex(attester.clone()), &index);

        // Extend TTLs
        env.storage().persistent().extend_ttl(&key, LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);
        env.storage().persistent().extend_ttl(&DataKey::AttestersList, LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);
        env.storage().instance().extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);

        env.events().publish((Symbol::new(&env, "attester_registered"),), attester);
    }

    pub fn deregister_attester(env: Env, attester: BytesN<32>) {
        Self::require_owner(&env);
        let key = DataKey::Attester(attester.clone());
        if !env.storage().persistent().has(&key) || !env.storage().persistent().get::<_, bool>(&key).unwrap() {
            panic!("attester not registered");
        }

        // Swap-and-pop using attester_index for O(1)
        let index: u32 = env.storage().persistent()
            .get(&DataKey::AttesterIndex(attester.clone())).unwrap();
        let mut attesters: Vec<BytesN<32>> = env.storage().persistent()
            .get(&DataKey::AttestersList).unwrap();
        let last_index = attesters.len() - 1;

        if index != last_index {
            let last_attester = attesters.get(last_index).unwrap();
            attesters.set(index, last_attester.clone());
            env.storage().persistent().set(&DataKey::AttesterIndex(last_attester), &index);
        }
        attesters.pop_back();

        env.storage().persistent().set(&DataKey::AttestersList, &attesters);
        env.storage().persistent().set(&key, &false);
        env.storage().persistent().remove(&DataKey::AttesterIndex(attester.clone()));

        env.events().publish((Symbol::new(&env, "attester_deregistered"),), attester);
    }

    pub fn get_registered_attesters(env: Env) -> Vec<BytesN<32>> {
        env.storage().persistent()
            .get(&DataKey::AttestersList)
            .unwrap_or(Vec::new(&env))
    }

    pub fn is_attester_registered(env: Env, attester: BytesN<32>) -> bool {
        env.storage().persistent()
            .get(&DataKey::Attester(attester))
            .unwrap_or(false)
    }
```

- [ ] **Step 10: Run tests**

Run: `cd soroban && cargo test -p predicate-registry`
Expected: PASS

- [ ] **Step 10a: Commit attester management**

```bash
git add soroban/predicate-registry/
git commit -m "feat(soroban): predicate-registry init, ownership, attester management"
```

### Step Group D: Policy Management

- [ ] **Step 11: Write policy tests**

```rust
    #[test]
    fn test_set_get_policy() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        let client_addr = Address::generate(&env);
        let policy = String::from_str(&env, "x-abc123");
        client.set_policy_id(&client_addr, &policy);
        assert_eq!(client.get_policy_id(&client_addr), policy);
    }

    #[test]
    #[should_panic]
    fn test_set_policy_not_authorized() {
        let env = Env::default();
        // Don't mock auths — client_addr.require_auth() will fail
        let (_owner, client) = setup_registry(&env);
        let client_addr = Address::generate(&env);
        let policy = String::from_str(&env, "x-abc123");
        client.set_policy_id(&client_addr, &policy);
    }
```

- [ ] **Step 12: Implement policy management**

```rust
    pub fn set_policy_id(env: Env, client: Address, policy_id: String) {
        client.require_auth();
        env.storage().persistent().set(&DataKey::Policy(client.clone()), &policy_id);
        env.storage().persistent().extend_ttl(
            &DataKey::Policy(client.clone()), LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT
        );
        env.events().publish(
            (Symbol::new(&env, "policy_set"), client),
            policy_id,
        );
    }

    pub fn get_policy_id(env: Env, client: Address) -> String {
        env.storage().persistent()
            .get(&DataKey::Policy(client))
            .unwrap_or(String::from_str(&env, ""))
    }
```

- [ ] **Step 13: Run tests**

Run: `cd soroban && cargo test -p predicate-registry`
Expected: PASS

### Step Group E: Attestation Validation

- [ ] **Step 14: Write attestation validation tests**

These tests require Ed25519 key generation. The `soroban-sdk` testutils provide `env.crypto()` for this.

```rust
    use soroban_sdk::testutils::Ledger;
    use ed25519_dalek::Signer;

    fn create_keypair(env: &Env, seed: u8) -> (BytesN<32>, ed25519_dalek::SigningKey) {
        let secret_bytes = [seed; 32];
        let signing_key = ed25519_dalek::SigningKey::from_bytes(&secret_bytes);
        let verifying_key = signing_key.verifying_key();
        let pubkey = BytesN::from_array(env, &verifying_key.to_bytes());
        (pubkey, signing_key)
    }

    fn sign_statement(env: &Env, signing_key: &ed25519_dalek::SigningKey, statement: &Statement) -> BytesN<64> {
        let message = predicate_client::serialize_statement(env, statement);
        // Convert Soroban Bytes to a Vec<u8> for ed25519-dalek signing
        let len = message.len() as usize;
        let mut buf = alloc::vec![0u8; len];
        message.copy_into_slice(&mut buf);
        let sig = signing_key.sign(&buf);
        BytesN::from_array(env, &sig.to_bytes())
    }

    // Note: soroban-sdk provides an allocator, so alloc::vec is available in tests.
    // Add `extern crate alloc;` at the top of the test module if needed.

    #[test]
    fn test_valid_attestation() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);

        // Register attester
        let (pubkey, signing_key) = create_keypair(&env, 1);
        client.register_attester(&pubkey);

        // Set up ledger timestamp
        env.ledger().with_mut(|li| {
            li.timestamp = 1000;
        });

        // Create statement
        let statement = Statement {
            uuid: String::from_str(&env, "uuid-1"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 2000u64,
        };

        // Sign it
        let signature = sign_statement(&env, &signing_key, &statement);
        let attestation = Attestation {
            uuid: String::from_str(&env, "uuid-1"),
            expiration: 2000u64,
            attester: pubkey,
            signature,
        };

        // Should not panic
        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "expired")]
    fn test_expired_attestation() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        let (pubkey, signing_key) = create_keypair(&env, 1);
        client.register_attester(&pubkey);

        env.ledger().with_mut(|li| { li.timestamp = 3000; });

        let statement = Statement {
            uuid: String::from_str(&env, "uuid-expired"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 2000u64,
        };
        let signature = sign_statement(&env, &signing_key, &statement);
        let attestation = Attestation {
            uuid: String::from_str(&env, "uuid-expired"),
            expiration: 2000u64,
            attester: pubkey,
            signature,
        };
        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "UUID already used")]
    fn test_replayed_uuid() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        let (pubkey, signing_key) = create_keypair(&env, 1);
        client.register_attester(&pubkey);

        env.ledger().with_mut(|li| { li.timestamp = 1000; });

        let statement = Statement {
            uuid: String::from_str(&env, "uuid-replay"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 2000u64,
        };
        let signature = sign_statement(&env, &signing_key, &statement);
        let attestation = Attestation {
            uuid: String::from_str(&env, "uuid-replay"),
            expiration: 2000u64,
            attester: pubkey.clone(),
            signature: signature.clone(),
        };

        client.validate_attestation(&statement, &attestation);
        // Second call with same UUID should panic
        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "not registered")]
    fn test_unregistered_attester() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        // Don't register the attester
        let (pubkey, signing_key) = create_keypair(&env, 1);

        env.ledger().with_mut(|li| { li.timestamp = 1000; });

        let statement = Statement {
            uuid: String::from_str(&env, "uuid-unreg"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 2000u64,
        };
        let signature = sign_statement(&env, &signing_key, &statement);
        let attestation = Attestation {
            uuid: String::from_str(&env, "uuid-unreg"),
            expiration: 2000u64,
            attester: pubkey,
            signature,
        };
        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic] // Ed25519 verify panics on bad sig
    fn test_invalid_signature() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        let (pubkey, _) = create_keypair(&env, 1);
        client.register_attester(&pubkey);

        env.ledger().with_mut(|li| { li.timestamp = 1000; });

        let statement = Statement {
            uuid: String::from_str(&env, "uuid-badsig"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 2000u64,
        };
        // Use a garbage signature
        let bad_sig = BytesN::from_array(&env, &[0u8; 64]);
        let attestation = Attestation {
            uuid: String::from_str(&env, "uuid-badsig"),
            expiration: 2000u64,
            attester: pubkey,
            signature: bad_sig,
        };
        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "UUID mismatch")]
    fn test_uuid_mismatch() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        let (pubkey, signing_key) = create_keypair(&env, 1);
        client.register_attester(&pubkey);
        env.ledger().with_mut(|li| { li.timestamp = 1000; });

        let statement = Statement {
            uuid: String::from_str(&env, "uuid-a"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 2000u64,
        };
        let signature = sign_statement(&env, &signing_key, &statement);
        let attestation = Attestation {
            uuid: String::from_str(&env, "uuid-b"), // Different UUID
            expiration: 2000u64,
            attester: pubkey,
            signature,
        };
        client.validate_attestation(&statement, &attestation);
    }

    #[test]
    #[should_panic(expected = "expiration mismatch")]
    fn test_expiration_mismatch() {
        let env = Env::default();
        env.mock_all_auths();
        let (_owner, client) = setup_registry(&env);
        let (pubkey, signing_key) = create_keypair(&env, 1);
        client.register_attester(&pubkey);
        env.ledger().with_mut(|li| { li.timestamp = 1000; });

        let statement = Statement {
            uuid: String::from_str(&env, "uuid-exp"),
            msg_sender: Address::generate(&env),
            target: Address::generate(&env),
            msg_value: 0i128,
            encoded_sig_and_args: Bytes::new(&env),
            policy: String::from_str(&env, "policy-1"),
            expiration: 2000u64,
        };
        let signature = sign_statement(&env, &signing_key, &statement);
        let attestation = Attestation {
            uuid: String::from_str(&env, "uuid-exp"),
            expiration: 3000u64, // Different expiration
            attester: pubkey,
            signature,
        };
        client.validate_attestation(&statement, &attestation);
    }
```

- [ ] **Step 15: Implement validate_attestation and hash_statement**

```rust
    pub fn validate_attestation(env: Env, statement: Statement, attestation: Attestation) {
        // 1. Check expiration
        let now = env.ledger().timestamp();
        if now > attestation.expiration {
            panic!("attestation expired");
        }

        // 2. UUID match
        if statement.uuid != attestation.uuid {
            panic!("UUID mismatch");
        }

        // 3. Expiration match
        if statement.expiration != attestation.expiration {
            panic!("expiration mismatch");
        }

        // 4. UUID not spent
        let uuid_key = DataKey::UsedUuid(statement.uuid.clone());
        if env.storage().persistent().has(&uuid_key) {
            panic!("UUID already used");
        }

        // 5. Attester registered (fail fast before crypto)
        if !Self::is_attester_registered(env.clone(), attestation.attester.clone()) {
            panic!("attester not registered");
        }

        // 6. Serialize statement and verify signature
        let message = predicate_client::serialize_statement(&env, &statement);
        env.crypto().ed25519_verify(
            &attestation.attester,
            &message,
            &attestation.signature,
        );

        // 7. Mark UUID as spent
        env.storage().persistent().set(&uuid_key, &true);
        env.storage().persistent().extend_ttl(&uuid_key, LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);

        // 8. Emit event
        env.events().publish(
            (Symbol::new(&env, "statement_validated"),),
            (
                statement.msg_sender,
                statement.target,
                attestation.attester,
                statement.policy,
                statement.uuid,
            ),
        );
    }

    /// Returns the serialized message bytes for a statement.
    /// Off-chain attesters call this to get the exact bytes to sign with Ed25519.
    /// Note: Attesters sign the raw bytes directly — Ed25519 handles internal hashing.
    pub fn hash_statement(env: Env, statement: Statement) -> Bytes {
        predicate_client::serialize_statement(&env, &statement)
    }
```

- [ ] **Step 16: Run tests**

Run: `cd soroban && cargo test -p predicate-registry`
Expected: All PASS

- [ ] **Step 17: Add extend_ttl admin function**

```rust
    pub fn extend_ttl(env: Env) {
        Self::require_owner(&env);
        env.storage().instance().extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);
        if env.storage().persistent().has(&DataKey::AttestersList) {
            env.storage().persistent().extend_ttl(
                &DataKey::AttestersList, LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT
            );
        }
    }
```

- [ ] **Step 18: Commit**

```bash
git add soroban/predicate-registry/
git commit -m "feat(soroban): implement predicate-registry contract"
```

---

## Task 4: test-stablecoin — Freezable Token Contract

**Files:**
- Modify: `soroban/test-stablecoin/src/lib.rs`

### Step Group A: Storage and Initialization

- [ ] **Step 1: Write initialization test**

```rust
#[cfg(test)]
mod test {
    use super::*;
    use soroban_sdk::testutils::Address as _;
    use soroban_sdk::Env;

    fn setup_token(env: &Env) -> (Address, TestStablecoinContractClient) {
        let contract_id = env.register(TestStablecoinContract, ());
        let client = TestStablecoinContractClient::new(env, &contract_id);
        let admin = Address::generate(env);
        client.initialize(
            &admin,
            &6u32,
            &String::from_str(env, "Test USD"),
            &String::from_str(env, "TUSD"),
        );
        (admin, client)
    }

    #[test]
    fn test_initialize() {
        let env = Env::default();
        let (_admin, client) = setup_token(&env);
        assert_eq!(client.decimals(), 6);
        assert_eq!(client.name(), String::from_str(&env, "Test USD"));
        assert_eq!(client.symbol(), String::from_str(&env, "TUSD"));
    }

    #[test]
    #[should_panic(expected = "already initialized")]
    fn test_double_initialize() {
        let env = Env::default();
        let (admin, client) = setup_token(&env);
        client.initialize(
            &admin, &6u32,
            &String::from_str(&env, "Test USD"),
            &String::from_str(&env, "TUSD"),
        );
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd soroban && cargo test -p test-stablecoin`
Expected: FAIL

- [ ] **Step 3: Implement storage keys and initialize**

```rust
#![no_std]
use soroban_sdk::{
    contract, contractimpl, contracttype, token, Address, Env, String, Symbol,
};
use soroban_token_sdk::TokenUtils;

const LEDGER_BUMP_AMOUNT: u32 = 518_400;
const LEDGER_THRESHOLD: u32 = 432_000;
const BALANCE_BUMP_AMOUNT: u32 = 518_400;
const BALANCE_THRESHOLD: u32 = 432_000;

#[contracttype]
#[derive(Clone)]
enum DataKey {
    Admin,
    ComplianceAdmin,
    Initialized,
    Balance(Address),
    Allowance(Address, Address), // (from, spender)
    Frozen(Address),
    Name,
    Symbol,
    Decimals,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AllowanceData {
    pub amount: i128,
    pub expiration_ledger: u32,
}

#[contract]
pub struct TestStablecoinContract;

#[contractimpl]
impl TestStablecoinContract {
    pub fn initialize(env: Env, admin: Address, decimal: u32, name: String, symbol: String) {
        if env.storage().instance().has(&DataKey::Initialized) {
            panic!("already initialized");
        }
        env.storage().instance().set(&DataKey::Initialized, &true);
        env.storage().instance().set(&DataKey::Admin, &admin);
        env.storage().instance().set(&DataKey::Decimals, &decimal);
        env.storage().instance().set(&DataKey::Name, &name);
        env.storage().instance().set(&DataKey::Symbol, &symbol);
        env.storage().instance().extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd soroban && cargo test -p test-stablecoin`
Expected: PASS

### Step Group B: Mint and Balance

- [ ] **Step 5: Write mint/balance tests**

```rust
    #[test]
    fn test_mint() {
        let env = Env::default();
        env.mock_all_auths();
        let (_admin, client) = setup_token(&env);
        let user = Address::generate(&env);
        client.mint(&user, &1000_000000i128); // 1000 with 6 decimals
        assert_eq!(client.balance(&user), 1000_000000i128);
    }

    #[test]
    #[should_panic]
    fn test_mint_not_admin() {
        let env = Env::default();
        // Don't mock auths
        let (_admin, client) = setup_token(&env);
        let user = Address::generate(&env);
        client.mint(&user, &1000i128);
    }
```

- [ ] **Step 6: Implement mint, balance, and admin helpers**

```rust
    fn require_admin(env: &Env) {
        let admin: Address = env.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();
    }

    pub fn mint(env: Env, to: Address, amount: i128) {
        Self::require_admin(&env);
        assert!(amount > 0, "amount must be positive");
        let key = DataKey::Balance(to.clone());
        let balance: i128 = env.storage().persistent().get(&key).unwrap_or(0);
        env.storage().persistent().set(&key, &(balance + amount));
        env.storage().persistent().extend_ttl(&key, BALANCE_THRESHOLD, BALANCE_BUMP_AMOUNT);
        env.storage().instance().extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);

        TokenUtils::new(&env).events().mint(
            env.storage().instance().get::<_, Address>(&DataKey::Admin).unwrap(),
            to,
            amount,
        );
    }

    pub fn balance(env: Env, id: Address) -> i128 {
        env.storage().persistent()
            .get(&DataKey::Balance(id))
            .unwrap_or(0)
    }

    pub fn decimals(env: Env) -> u32 {
        env.storage().instance().get(&DataKey::Decimals).unwrap()
    }

    pub fn name(env: Env) -> String {
        env.storage().instance().get(&DataKey::Name).unwrap()
    }

    pub fn symbol(env: Env) -> String {
        env.storage().instance().get(&DataKey::Symbol).unwrap()
    }
```

- [ ] **Step 7: Run tests**

Run: `cd soroban && cargo test -p test-stablecoin`
Expected: PASS

### Step Group C: Transfer with Freeze Checks

- [ ] **Step 8: Write transfer and freeze tests**

```rust
    #[test]
    fn test_transfer() {
        let env = Env::default();
        env.mock_all_auths();
        let (_admin, client) = setup_token(&env);
        let user1 = Address::generate(&env);
        let user2 = Address::generate(&env);
        client.mint(&user1, &1000i128);
        client.transfer(&user1, &user2, &400i128);
        assert_eq!(client.balance(&user1), 600i128);
        assert_eq!(client.balance(&user2), 400i128);
    }

    #[test]
    #[should_panic]
    fn test_transfer_insufficient() {
        let env = Env::default();
        env.mock_all_auths();
        let (_admin, client) = setup_token(&env);
        let user1 = Address::generate(&env);
        let user2 = Address::generate(&env);
        client.mint(&user1, &100i128);
        client.transfer(&user1, &user2, &200i128);
    }

    #[test]
    #[should_panic(expected = "frozen")]
    fn test_freeze_blocks_transfer_from() {
        let env = Env::default();
        env.mock_all_auths();
        let (admin, client) = setup_token(&env);
        let compliance = Address::generate(&env);
        client.set_compliance_admin(&compliance);
        let user1 = Address::generate(&env);
        let user2 = Address::generate(&env);
        client.mint(&user1, &1000i128);
        client.freeze(&user1);
        client.transfer(&user1, &user2, &100i128);
    }

    #[test]
    #[should_panic(expected = "frozen")]
    fn test_freeze_blocks_transfer_to() {
        let env = Env::default();
        env.mock_all_auths();
        let (admin, client) = setup_token(&env);
        let compliance = Address::generate(&env);
        client.set_compliance_admin(&compliance);
        let user1 = Address::generate(&env);
        let user2 = Address::generate(&env);
        client.mint(&user1, &1000i128);
        client.freeze(&user2);
        client.transfer(&user1, &user2, &100i128);
    }

    #[test]
    fn test_unfreeze_restores_transfer() {
        let env = Env::default();
        env.mock_all_auths();
        let (admin, client) = setup_token(&env);
        let compliance = Address::generate(&env);
        client.set_compliance_admin(&compliance);
        let user1 = Address::generate(&env);
        let user2 = Address::generate(&env);
        client.mint(&user1, &1000i128);
        client.freeze(&user1);
        client.unfreeze(&user1);
        client.transfer(&user1, &user2, &100i128);
        assert_eq!(client.balance(&user2), 100i128);
    }
```

- [ ] **Step 9: Implement transfer, freeze, unfreeze, is_frozen**

```rust
    fn check_not_frozen(env: &Env, addr: &Address) {
        if env.storage().persistent()
            .get(&DataKey::Frozen(addr.clone()))
            .unwrap_or(false)
        {
            panic!("account is frozen");
        }
    }

    pub fn transfer(env: Env, from: Address, to: Address, amount: i128) {
        from.require_auth();
        assert!(amount > 0, "amount must be positive");
        Self::check_not_frozen(&env, &from);
        Self::check_not_frozen(&env, &to);

        let from_key = DataKey::Balance(from.clone());
        let to_key = DataKey::Balance(to.clone());
        let from_balance: i128 = env.storage().persistent().get(&from_key).unwrap_or(0);
        assert!(from_balance >= amount, "insufficient balance");

        env.storage().persistent().set(&from_key, &(from_balance - amount));
        let to_balance: i128 = env.storage().persistent().get(&to_key).unwrap_or(0);
        env.storage().persistent().set(&to_key, &(to_balance + amount));

        env.storage().persistent().extend_ttl(&from_key, BALANCE_THRESHOLD, BALANCE_BUMP_AMOUNT);
        env.storage().persistent().extend_ttl(&to_key, BALANCE_THRESHOLD, BALANCE_BUMP_AMOUNT);

        TokenUtils::new(&env).events().transfer(from, to, amount);
    }

    pub fn freeze(env: Env, account: Address) {
        Self::require_compliance_admin(&env);
        env.storage().persistent().set(&DataKey::Frozen(account.clone()), &true);
        env.storage().persistent().extend_ttl(
            &DataKey::Frozen(account.clone()), LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT
        );
        env.events().publish(
            (Symbol::new(&env, "freeze"),),
            account,
        );
    }

    pub fn unfreeze(env: Env, account: Address) {
        Self::require_compliance_admin(&env);
        env.storage().persistent().set(&DataKey::Frozen(account.clone()), &false);
        env.events().publish(
            (Symbol::new(&env, "unfreeze"),),
            account,
        );
    }

    pub fn is_frozen(env: Env, account: Address) -> bool {
        env.storage().persistent()
            .get(&DataKey::Frozen(account))
            .unwrap_or(false)
    }

    fn require_compliance_admin(env: &Env) {
        let compliance_admin: Address = env.storage().instance()
            .get(&DataKey::ComplianceAdmin)
            .expect("compliance admin not set");
        compliance_admin.require_auth();
    }
```

- [ ] **Step 10: Run tests**

Run: `cd soroban && cargo test -p test-stablecoin`
Expected: PASS

### Step Group D: Compliance Admin, Burn, Approve, Transfer_from

- [ ] **Step 11: Write remaining tests**

```rust
    #[test]
    fn test_set_compliance_admin() {
        let env = Env::default();
        env.mock_all_auths();
        let (_admin, client) = setup_token(&env);
        let compliance = Address::generate(&env);
        client.set_compliance_admin(&compliance);
        // Verify by freezing (only compliance admin can)
        let user = Address::generate(&env);
        client.freeze(&user);
        assert!(client.is_frozen(&user));
    }

    #[test]
    #[should_panic]
    fn test_set_compliance_admin_not_admin() {
        let env = Env::default();
        // Don't mock auths
        let (_admin, client) = setup_token(&env);
        let compliance = Address::generate(&env);
        client.set_compliance_admin(&compliance);
    }

    #[test]
    #[should_panic]
    fn test_freeze_not_compliance_admin() {
        let env = Env::default();
        env.mock_all_auths(); // Mock auths so setup works
        let (_admin, client) = setup_token(&env);
        let compliance = Address::generate(&env);
        client.set_compliance_admin(&compliance);
        // Now stop mocking and try to freeze as a non-compliance-admin
        // The compliance_admin.require_auth() will fail because the actual
        // invoker is not the compliance admin
        env.mock_auths(&[]); // Clear all mock auths
        let user = Address::generate(&env);
        client.freeze(&user);
    }

    #[test]
    fn test_burn() {
        let env = Env::default();
        env.mock_all_auths();
        let (_admin, client) = setup_token(&env);
        let user = Address::generate(&env);
        client.mint(&user, &1000i128);
        client.burn(&user, &300i128);
        assert_eq!(client.balance(&user), 700i128);
    }

    #[test]
    #[should_panic(expected = "frozen")]
    fn test_burn_frozen_account() {
        let env = Env::default();
        env.mock_all_auths();
        let (_admin, client) = setup_token(&env);
        let compliance = Address::generate(&env);
        client.set_compliance_admin(&compliance);
        let user = Address::generate(&env);
        client.mint(&user, &1000i128);
        client.freeze(&user);
        client.burn(&user, &100i128);
    }

    #[test]
    fn test_mint_to_frozen() {
        let env = Env::default();
        env.mock_all_auths();
        let (_admin, client) = setup_token(&env);
        let compliance = Address::generate(&env);
        client.set_compliance_admin(&compliance);
        let user = Address::generate(&env);
        client.freeze(&user);
        client.mint(&user, &1000i128); // Should succeed
        assert_eq!(client.balance(&user), 1000i128);
    }

    #[test]
    fn test_approve_and_transfer_from() {
        let env = Env::default();
        env.mock_all_auths();
        let (_admin, client) = setup_token(&env);
        let user1 = Address::generate(&env);
        let spender = Address::generate(&env);
        let user2 = Address::generate(&env);
        client.mint(&user1, &1000i128);

        env.ledger().with_mut(|li| { li.sequence_number = 100; });
        client.approve(&user1, &spender, &500i128, &200u32);
        assert_eq!(client.allowance(&user1, &spender), 500i128);

        client.transfer_from(&spender, &user1, &user2, &200i128);
        assert_eq!(client.balance(&user1), 800i128);
        assert_eq!(client.balance(&user2), 200i128);
        assert_eq!(client.allowance(&user1, &spender), 300i128);
    }

    #[test]
    #[should_panic(expected = "frozen")]
    fn test_transfer_from_frozen() {
        let env = Env::default();
        env.mock_all_auths();
        let (_admin, client) = setup_token(&env);
        let compliance = Address::generate(&env);
        client.set_compliance_admin(&compliance);
        let user1 = Address::generate(&env);
        let spender = Address::generate(&env);
        let user2 = Address::generate(&env);
        client.mint(&user1, &1000i128);
        env.ledger().with_mut(|li| { li.sequence_number = 100; });
        client.approve(&user1, &spender, &500i128, &200u32);
        client.freeze(&user1);
        client.transfer_from(&spender, &user1, &user2, &100i128);
    }
```

- [ ] **Step 12: Implement set_compliance_admin, set_admin, burn, burn_from, approve, transfer_from, allowance**

```rust
    pub fn set_compliance_admin(env: Env, new_admin: Address) {
        Self::require_admin(&env);
        env.storage().instance().set(&DataKey::ComplianceAdmin, &new_admin);
        env.storage().instance().extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);
        env.events().publish(
            (Symbol::new(&env, "set_compliance_admin"),),
            new_admin,
        );
    }

    pub fn set_admin(env: Env, new_admin: Address) {
        Self::require_admin(&env);
        env.storage().instance().set(&DataKey::Admin, &new_admin);
        env.storage().instance().extend_ttl(LEDGER_THRESHOLD, LEDGER_BUMP_AMOUNT);
    }

    pub fn burn(env: Env, from: Address, amount: i128) {
        from.require_auth();
        assert!(amount > 0, "amount must be positive");
        Self::check_not_frozen(&env, &from);
        let key = DataKey::Balance(from.clone());
        let balance: i128 = env.storage().persistent().get(&key).unwrap_or(0);
        assert!(balance >= amount, "insufficient balance");
        env.storage().persistent().set(&key, &(balance - amount));
        env.storage().persistent().extend_ttl(&key, BALANCE_THRESHOLD, BALANCE_BUMP_AMOUNT);
        TokenUtils::new(&env).events().burn(from, amount);
    }

    pub fn burn_from(env: Env, spender: Address, from: Address, amount: i128) {
        spender.require_auth();
        assert!(amount > 0, "amount must be positive");
        Self::check_not_frozen(&env, &from);
        Self::spend_allowance(&env, &from, &spender, amount);
        let key = DataKey::Balance(from.clone());
        let balance: i128 = env.storage().persistent().get(&key).unwrap_or(0);
        assert!(balance >= amount, "insufficient balance");
        env.storage().persistent().set(&key, &(balance - amount));
        env.storage().persistent().extend_ttl(&key, BALANCE_THRESHOLD, BALANCE_BUMP_AMOUNT);
        TokenUtils::new(&env).events().burn(from, amount);
    }

    pub fn approve(env: Env, from: Address, spender: Address, amount: i128, expiration_ledger: u32) {
        from.require_auth();
        let key = DataKey::Allowance(from.clone(), spender.clone());
        let allowance = AllowanceData { amount, expiration_ledger };
        env.storage().temporary().set(&key, &allowance);
        if amount > 0 {
            env.storage().temporary().extend_ttl(
                &key,
                expiration_ledger.saturating_sub(env.ledger().sequence()),
                expiration_ledger.saturating_sub(env.ledger().sequence()),
            );
        }
        TokenUtils::new(&env).events().approve(from, spender, amount, expiration_ledger);
    }

    pub fn allowance(env: Env, from: Address, spender: Address) -> i128 {
        let key = DataKey::Allowance(from, spender);
        if let Some(allowance) = env.storage().temporary().get::<_, AllowanceData>(&key) {
            if allowance.expiration_ledger < env.ledger().sequence() {
                0
            } else {
                allowance.amount
            }
        } else {
            0
        }
    }

    pub fn transfer_from(env: Env, spender: Address, from: Address, to: Address, amount: i128) {
        spender.require_auth();
        assert!(amount > 0, "amount must be positive");
        Self::check_not_frozen(&env, &from);
        Self::check_not_frozen(&env, &to);
        Self::spend_allowance(&env, &from, &spender, amount);

        let from_key = DataKey::Balance(from.clone());
        let to_key = DataKey::Balance(to.clone());
        let from_balance: i128 = env.storage().persistent().get(&from_key).unwrap_or(0);
        assert!(from_balance >= amount, "insufficient balance");
        env.storage().persistent().set(&from_key, &(from_balance - amount));
        let to_balance: i128 = env.storage().persistent().get(&to_key).unwrap_or(0);
        env.storage().persistent().set(&to_key, &(to_balance + amount));

        env.storage().persistent().extend_ttl(&from_key, BALANCE_THRESHOLD, BALANCE_BUMP_AMOUNT);
        env.storage().persistent().extend_ttl(&to_key, BALANCE_THRESHOLD, BALANCE_BUMP_AMOUNT);

        TokenUtils::new(&env).events().transfer(from, to, amount);
    }

    fn spend_allowance(env: &Env, from: &Address, spender: &Address, amount: i128) {
        let key = DataKey::Allowance(from.clone(), spender.clone());
        let mut allowance: AllowanceData = env.storage().temporary().get(&key)
            .expect("no allowance set");
        assert!(allowance.expiration_ledger >= env.ledger().sequence(), "allowance expired");
        assert!(allowance.amount >= amount, "insufficient allowance");
        allowance.amount -= amount;
        env.storage().temporary().set(&key, &allowance);
    }
```

- [ ] **Step 13: Run all stablecoin tests**

Run: `cd soroban && cargo test -p test-stablecoin`
Expected: All PASS

- [ ] **Step 14: Commit**

```bash
git add soroban/test-stablecoin/
git commit -m "feat(soroban): implement test-stablecoin with freeze support"
```

---

## Task 5: predicate-client Integration Test

**Files:**
- Modify: `soroban/predicate-client/src/lib.rs`

- [ ] **Step 1: Write integration test in predicate-registry**

Note: `ed25519-dalek` was already added as a workspace dev-dependency in Task 1.

Add an integration test that exercises the full flow: client lib constructs a statement, calls authorize_transaction, which invokes the registry:

```rust
    #[test]
    fn test_authorize_transaction_integration() {
        let env = Env::default();
        env.mock_all_auths();

        // Deploy registry
        let (owner, registry_client) = setup_registry(&env);
        let registry_addr = /* registry contract address */;

        // Register attester
        let (pubkey, signing_key) = create_keypair(&env, 1);
        registry_client.register_attester(&pubkey);

        env.ledger().with_mut(|li| { li.timestamp = 1000; });

        // Build attestation
        let attestation = Attestation { /* ... */ };
        let encoded_args = Bytes::new(&env);
        let sender = Address::generate(&env);
        let policy = String::from_str(&env, "policy-1");

        // This should succeed via cross-contract call
        predicate_client::authorize_transaction(
            &env, &registry_addr, &attestation, &encoded_args, &sender, 0, &policy
        );
    }
```

- [ ] **Step 2: Run integration test**

Run: `cd soroban && cargo test -p predicate-registry -- test_authorize_transaction`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add soroban/
git commit -m "feat(soroban): add predicate-client integration test"
```

---

## Task 6: CI/CD Updates

**Files:**
- Modify: `.github/workflows/contracts.yml`
- Modify: `.github/workflows/publish.yml`

- [ ] **Step 1: Add soroban-build-test job to contracts.yml**

Add after the existing `fmt` job:

```yaml
    soroban-build:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4

          - name: Install Rust
            uses: dtolnay/rust-toolchain@stable
            with:
              targets: wasm32-unknown-unknown

          - name: Cache cargo
            uses: actions/cache@v3
            with:
              path: |
                ~/.cargo/registry
                ~/.cargo/git
                soroban/target
              key: ${{ runner.os }}-cargo-${{ hashFiles('soroban/**/Cargo.toml') }}
              restore-keys: |
                ${{ runner.os }}-cargo-

          - name: Install Stellar CLI
            run: cargo install stellar-cli --locked

          - name: Build Soroban contracts
            run: cd soroban && stellar contract build

          - name: Test Soroban contracts
            run: cd soroban && cargo test

          - name: Check Rust formatting
            run: cd soroban && cargo fmt --check
```

- [ ] **Step 2: Add Soroban publishing steps to publish.yml**

After the existing Foundry publish step, add:

```yaml
      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: wasm32-unknown-unknown

      - name: Install Stellar CLI
        run: cargo install stellar-cli --locked

      - name: Build Soroban contracts
        run: cd soroban && stellar contract build

      - name: Publish Soroban artifacts
        env:
          CONTRAFACTORY_SERVER: ${{ secrets.CONTRAFACTORY_SERVER }}
          CONTRAFACTORY_API_KEY: ${{ secrets.CONTRAFACTORY_API_KEY }}
        run: |
          # Note: Exact contrafactory CLI commands for WASM artifacts need
          # coordination with Contrafactory team. Placeholder commands below.
          echo "TODO: Publish stellar-test-stablecoin WASM"
          echo "TODO: Publish stellar-predicate-registry WASM"
          # contrafactory publish stellar-test-stablecoin \
          #   --artifact wasm:soroban/target/wasm32-unknown-unknown/release/test_stablecoin.wasm \
          #   --version ${{ steps.version.outputs.version }}
          # contrafactory publish stellar-predicate-registry \
          #   --artifact wasm:soroban/target/wasm32-unknown-unknown/release/predicate_registry.wasm \
          #   --version ${{ steps.version.outputs.version }}
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/
git commit -m "ci: add Soroban build, test, and publish to CI/CD"
```

---

## Task 7: README and Final Verification

**Files:**
- Create: `soroban/README.md`

- [ ] **Step 1: Write README**

```markdown
# Soroban Contracts

Predicate compliance contracts for the Stellar/Soroban ecosystem.

## Contracts

- **predicate-registry** — Attester management, policy binding, Ed25519 attestation validation
- **test-stablecoin** — SAC-compatible token with freeze/compliance support and RBAC
- **predicate-client** — Shared types and helpers for Predicate integration (library, not deployed)

## Build

```bash
stellar contract build
```

## Test

```bash
cargo test
```

## Architecture

See `docs/superpowers/specs/2026-03-24-soroban-contracts-design.md` for the full design spec.
```

- [ ] **Step 2: Run full test suite**

Run: `cd soroban && cargo test`
Expected: All tests pass across all three crates.

- [ ] **Step 3: Build WASM artifacts**

Run: `cd soroban && stellar contract build` (requires stellar-cli and wasm32 target)
If stellar-cli is not installed, verify with: `cd soroban && cargo build --target wasm32-unknown-unknown --release`
Expected: WASM files in `soroban/target/wasm32-unknown-unknown/release/`

- [ ] **Step 4: Commit**

```bash
git add soroban/README.md
git commit -m "docs(soroban): add README for Soroban contracts"
```

- [ ] **Step 5: Verify existing EVM tests still pass**

Run: `forge test` (from repo root)
Expected: All existing EVM tests still pass — Soroban changes are isolated.
