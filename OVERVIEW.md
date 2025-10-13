# Predicate Contracts v2 - Technical Overview

## Introduction

Predicate Contracts v2 is a simplified, production-ready implementation of the Predicate protocol for on-chain compliance verification. This version provides a streamlined architecture for integrating policy-based attestation validation into smart contracts.

## Architecture Components

### 1. PredicateRegistry (Simplified ServiceManager)

The `PredicateRegistry` is the core registry contract that manages attesters, policies, and validates attestations. It replaces the more complex ServiceManager architecture from v1.

**Location**: `src/PredicateRegistry.sol`

#### Key Simplifications from v1:

| Feature | v1 (ServiceManager) | v2 (PredicateRegistry) |
|---------|-------------------|----------------------|
| **Architecture** | Multiple service components | Single unified contract |
| **Attester Model** | Quorum-based validation | Single attester signature |
| **Policy Structure** | Complex policy objects | Simple string identifiers |
| **Replay Protection** | Block-based nonces | UUID-based with expiration |
| **Hash Functions** | Single hash method | Dual: `hashTaskWithExpiry` + `hashTaskSafe` |

#### Core Methods:

```solidity
// Attester Management (Owner only)
function registerAttester(address _attester) external onlyOwner
function deregisterAttester(address _attester) external onlyOwner
function getRegisteredAttesters() external view returns (address[])

// Policy Management
function setPolicy(string memory _policy) external  // Clients set their own policy
function getPolicy(address _client) external view returns (string memory)

// Attestation Validation
function validateAttestation(Task calldata _task, Attestation calldata _attestation) external returns (bool)

// Hashing Utilities
function hashTaskWithExpiry(Task calldata _task) public pure returns (bytes32)
function hashTaskSafe(Task calldata _task) public view returns (bytes32)
```

#### Security Features:

1. **Dual Hashing Strategy**:
   - `hashTaskWithExpiry()`: Basic hash for attester signing (uses `_task.target`)
   - `hashTaskSafe()`: Validation hash with `msg.sender` to prevent cross-contract replay attacks

2. **UUID-based Replay Protection**: Each task has a unique UUID that is marked as spent after validation

3. **Expiration Validation**: Attestations must be used before their expiration timestamp

4. **Signature Recovery**: Uses OpenZeppelin's ECDSA library for secure signature verification

#### Storage:

```solidity
address[] public registeredAttesters;                    // Array of registered attesters
mapping(address => bool) public isAttesterRegistered;    // Quick attester lookup
mapping(address => string) public clientToPolicy;        // Client => Policy ID
mapping(string => bool) public spentTaskIDs;             // UUID replay protection
```

---

### 2. PredicateClient (Customer Integration Mixin)

The `PredicateClient` is an abstract contract that customers inherit to integrate Predicate validation into their smart contracts.

**Location**: `src/mixins/PredicateClient.sol`

#### Key Features:

1. **ERC-7201 Namespaced Storage**: Prevents storage collisions in upgradeable contracts
   ```solidity
   bytes32 private constant _PREDICATE_CLIENT_STORAGE_SLOT = 
       0x804776a84f3d03ad8442127b1451e2fbbb6a715c681d6a83c9e9fca787b99300;
   ```

2. **Internal Authorization**: Core validation method for protected functions
   ```solidity
   function _authorizeTransaction(
       Attestation memory _attestation,
       bytes memory _encodedSigAndArgs,
       address _msgSender,
       uint256 _msgValue
   ) internal returns (bool)
   ```

3. **Configuration Methods**:
   ```solidity
   function _initPredicateClient(address _registryAddress, string memory _policy) internal
   function _setPolicy(string memory _policy) internal
   function _setRegistry(address _registryAddress) internal
   function _getPolicy() internal view returns (string memory)
   function _getRegistry() internal view returns (address)
   ```

#### Migration Guide for v1 → v2:

**Before (v1)**:
```solidity
contract MyContract {
    // Direct interaction with ServiceManager
    function doSomething(address recipient, uint256 amount) external {
        // Business logic
    }
}
```

**After (v2)**:
```solidity
import {PredicateClient} from "@predicate/mixins/PredicateClient.sol";
import {Attestation} from "@predicate/interfaces/IPredicateRegistry.sol";

contract MyContract is PredicateClient, Ownable {
    constructor(address _owner, address _registry, string memory _policy) Ownable(_owner) {
        _initPredicateClient(_registry, _policy);  // 1. Initialize
    }
    
    // 2. Add Attestation parameter
    function doSomething(
        address recipient, 
        uint256 amount,
        Attestation calldata _attestation  // NEW
    ) external payable {
        // 3. Encode internal function signature
        bytes memory encodedSigAndArgs = abi.encodeWithSignature(
            "_doSomethingInternal(address,uint256)", 
            recipient, 
            amount
        );
        
        // 4. Validate transaction
        require(
            _authorizeTransaction(_attestation, encodedSigAndArgs, msg.sender, msg.value),
            "MyContract: unauthorized transaction"
        );
        
        // 5. Execute business logic
        _doSomethingInternal(recipient, amount);
    }
    
    function _doSomethingInternal(address recipient, uint256 amount) internal {
        // Business logic here
    }
    
    // 6. Implement admin methods
    function setPolicy(string memory _policy) external onlyOwner {
        _setPolicy(_policy);
    }
    
    function setRegistry(address _registry) external onlyOwner {
        _setRegistry(_registry);
    }
}
```

**Migration Checklist**:
- ✅ Inherit from `PredicateClient`
- ✅ Call `_initPredicateClient(registry, policy)` in constructor
- ✅ Add `Attestation calldata _attestation` parameter to protected functions
- ✅ Encode function signature with `abi.encodeWithSignature()`
- ✅ Call `_authorizeTransaction()` before executing business logic
- ✅ Split public functions into public entry point + internal implementation
- ✅ Implement `setPolicy()` and `setRegistry()` admin functions

---

## Integration Patterns

v2 provides multiple integration patterns to suit different architectural needs:

### Pattern 1: Inheritance (Direct Integration)

**Location**: `src/examples/inheritance/MetaCoin.sol`

**When to use**: You want direct control and minimal dependencies.

**Architecture**:
```
User → MetaCoin (inherits PredicateClient) → PredicateRegistry
```

**Example**:
```solidity
contract MetaCoin is PredicateClient, Ownable {
    function sendCoin(address _receiver, uint256 _amount, Attestation calldata _attestation) 
        external 
        payable 
    {
        bytes memory encodedSigAndArgs = abi.encodeWithSignature(
            "_sendCoin(address,uint256)", 
            _receiver, 
            _amount
        );
        require(
            _authorizeTransaction(_attestation, encodedSigAndArgs, msg.sender, msg.value),
            "MetaCoin: unauthorized transaction"
        );
        _sendCoin(_receiver, _amount);
    }
}
```

**Pros**:
- ✅ Most direct integration
- ✅ Full control over validation flow
- ✅ No additional contracts required
- ✅ Lowest gas cost

**Cons**:
- ❌ Tighter coupling between business logic and validation
- ❌ Requires modifying function signatures
- ❌ Less modular

---

### Pattern 2: Proxy (Separation of Concerns)

**Location**: `src/examples/proxy/`

**When to use**: You want clean separation between validation logic and business logic, or need upgradeability.

**Architecture**:
```
User → PredicateClientProxy (inherits PredicateClient) → MetaCoin (inherits PredicateProtected)
                    ↓
              PredicateRegistry
```

**Components**:
- `PredicateClientProxy.sol`: Validates attestations, then forwards calls
- `PredicateProtected.sol`: Mixin that restricts function calls to authorized proxy
- Business contract: Pure business logic with `onlyPredicateProxy` modifier

**Example**:

```solidity
// Proxy Contract (handles validation)
contract PredicateClientProxy is PredicateClient {
    MetaCoin private _metaCoin;
    
    function proxySendCoin(
        address _receiver, 
        uint256 _amount, 
        Attestation calldata _attestation
    ) external payable {
        bytes memory encodedSigAndArgs = abi.encodeWithSignature(
            "_sendCoin(address,uint256)", 
            _receiver, 
            _amount
        );
        require(_authorizeTransaction(_attestation, encodedSigAndArgs, msg.sender, msg.value));
        _metaCoin.sendCoin{value: msg.value}(msg.sender, _receiver, _amount);
    }
}

// Business Contract (restricted to proxy)
contract MetaCoin is Ownable, PredicateProtected {
    function sendCoin(address _sender, address _receiver, uint256 _amount) 
        external 
        payable 
        onlyPredicateProxy  // Only proxy can call
    {
        _sendCoin(_sender, _receiver, _amount);
    }
}
```

**Pros**:
- ✅ Clean separation of concerns
- ✅ Business logic contract remains simpler
- ✅ Validation logic can be upgraded independently
- ✅ Business contract doesn't need to inherit PredicateClient

**Cons**:
- ❌ Additional gas cost for proxy deployment and calls
- ❌ More complex architecture
- ❌ Requires proxy management

---

### Pattern 3: Wrapper (External Validation)

**Status**: ❌ **Not Yet Implemented** (documented in README but code doesn't exist)

**Planned Location**: `src/examples/wrapper/` (to be implemented)

This pattern was planned to use an external validation contract with a modifier-based approach, but is not currently available in the codebase.

---

## Data Structures

### Task (Should be renamed to Statement)

Represents a transaction statement to be validated:

```solidity
struct Task {
    string uuid;                  // Unique identifier for the task
    address msgSender;            // Original transaction sender
    address target;               // Target contract (usually address(this))
    uint256 msgValue;             // ETH value sent with transaction
    bytes encodedSigAndArgs;      // Encoded function signature + arguments
    string policy;                // Policy ID for validation
    uint256 expiration;           // Expiration timestamp
}
```

**Note**: Despite the name "Task", this struct represents a **statement of intent** rather than an asynchronous task. It should be renamed to `Statement` for semantic clarity.

### Attestation

Represents an attester's signature authorizing a task:

```solidity
struct Attestation {
    string uuid;                  // Must match Task.uuid
    uint256 expiration;           // Must match Task.expiration
    address attester;             // Attester's address
    bytes signature;              // ECDSA signature over Task hash
}
```

---

## Validation Flow

```
1. User calls protected function with Attestation
         ↓
2. Contract calls _authorizeTransaction()
         ↓
3. Construct Task from parameters
         ↓
4. Call PredicateRegistry.validateAttestation(task, attestation)
         ↓
5. PredicateRegistry validates:
   - Attestation not expired
   - UUID not previously spent
   - UUID matches between Task and Attestation
   - Expiration matches between Task and Attestation
   - Signature is valid (ECDSA recovery)
   - Attester is registered
         ↓
6. Mark UUID as spent
         ↓
7. Emit TaskValidated event
         ↓
8. Return to contract, execute business logic
```

---

## Known Issues & Improvements Needed

### 1. Naming: Task → Statement

**Issue**: The codebase uses "Task" terminology, but the struct represents a "Statement" (a claim about intent, not an asynchronous task).

**Affected Items**:
- `struct Task` → `struct Statement`
- `TaskValidated` event → `StatementValidated`
- `spentTaskIDs` → `spentStatementUUIDs` or `usedStatementIDs`
- `hashTaskWithExpiry` → `hashStatementWithExpiry`
- `hashTaskSafe` → `hashStatementSafe`
- `validateAttestation(Task ...)` → `validateAttestation(Statement ...)`

### 2. Wrapper Pattern Documentation

**Issue**: README.md describes a wrapper pattern (`src/examples/wrapper/`) that doesn't exist in the codebase.

**Fix**: Either implement the pattern or update documentation to mark it as "planned/not yet available".

### 3. PredicateProtected Storage

**Issue**: `PredicateProtected.sol` line 8 has a comment: `// note: this should be namespaced storage in a real impl`

**Fix**: Implement ERC-7201 namespaced storage pattern (similar to PredicateClient).

---

## Architectural Improvements in v2

Compared to v1, v2 provides:

1. **Simplified Validation Model**: Single attester instead of quorum reduces complexity
2. **Cleaner Client Integration**: Mixin pattern with ERC-7201 storage for safer upgrades
3. **Better Replay Protection**: UUID-based with expiration instead of block-based nonces
4. **More Flexible Policies**: String-based identifiers instead of rigid structures
5. **Enhanced Security**: `hashTaskSafe()` prevents cross-contract replay attacks
6. **Gas Efficiency**: Simpler validation logic reduces gas costs
7. **Better Separation of Concerns**: Clear interfaces between Registry, Client, and Business Logic

---

## Testing

The test suite covers:
- ✅ Attester registration/deregistration
- ✅ Policy management
- ✅ Attestation validation (happy path)
- ✅ Expiration checks
- ✅ UUID tampering prevention
- ✅ Replay attack prevention
- ✅ Invalid signature handling
- ✅ Unregistered attester rejection
- ✅ Client integration (MetaCoin example)

**Test Files**:
- `test/PredicateRegistryAttestation.t.sol`
- `test/PredicateRegistryAttester.t.sol`
- `test/PredicateRegistryOwnership.t.sol`
- `test/Client.t.sol`

---

## Deployment Checklist

Before deploying to production:

1. ⚠️ Rename Task → Statement throughout codebase
2. ⚠️ Fix PredicateProtected storage (use ERC-7201 pattern)
3. ⚠️ Update README to clarify wrapper pattern status
4. ⚠️ Add deployment scripts
5. ⚠️ Complete security audit
6. ⚠️ Add comprehensive natspec documentation
7. ⚠️ Deploy to testnet and verify all integrations
8. ⚠️ Create migration guide for v1 users

---

## Resources

- **Main Repository**: `predicate-contracts`
- **License**: BUSL-1.1
- **Solidity Version**: ^0.8.12
- **Dependencies**: OpenZeppelin (Upgradeable, Cryptography)

For integration examples, see `src/examples/` directory.

