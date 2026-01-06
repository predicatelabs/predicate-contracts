# predicate-contracts 

Solidity library for creating compliant smart contracts application (e.g. Uniswap V4 hooks) using the Predicate network.

## Overview

Predicate Contracts v2 provides a simplified, production-ready implementation for on-chain compliance verification through attestation-based validation. This version features:

- **Simplified Architecture**: Single `PredicateRegistry` contract replacing complex ServiceManager
- **Easy Integration**: `PredicateClient` mixin for seamless integration into your contracts
- **Multiple Patterns**: Inheritance and Proxy patterns for different use cases
- **Enhanced Security**: ERC-7201 namespaced storage and statement-based validation
- **Production Ready**: Comprehensive test coverage and audit-ready code

See [OVERVIEW.md](./OVERVIEW.md) for detailed technical documentation.

## Quick Start

### Choosing Your PredicateClient Implementation

Predicate v2 offers two PredicateClient implementations optimized for different use cases:

#### **BasicPredicateClient** - Simplified for Most Use Cases
Use when your policy only needs:
- ✅ Allowlist/denylist of addresses
- ✅ Time-based restrictions
- ✅ Geographic/IP-based rules
- ✅ Simple compliance checks (KYC/AML status)

```solidity
import {BasicPredicateClient} from "@predicate/mixins/BasicPredicateClient.sol";
import {Attestation} from "@predicate/interfaces/IPredicateRegistry.sol";

contract SimpleVault is BasicPredicateClient {
    constructor(address _registry, string memory _policy) {
        _initPredicateClient(_registry, _policy);
    }
    
    function withdraw(uint256 amount, Attestation calldata attestation) external {
        // Simple authorization - no encoding needed!
        require(_authorizeTransaction(attestation, msg.sender), "Unauthorized");
        
        // Your business logic
        _processWithdrawal(amount);
    }
}
```

**Benefits:** Lower gas costs, simpler integration, cleaner code

#### **PredicateClient** - Full Control for Complex Policies
Use when your policy requires:
- ✅ Function-specific permissions (e.g., allow withdraw but not transfer)
- ✅ Value-based limits (e.g., max 10 ETH per transaction)
- ✅ Parameter validation (e.g., only send to whitelisted addresses)
- ✅ Different rules for different functions

```solidity
import {PredicateClient} from "@predicate/mixins/PredicateClient.sol";
import {Attestation} from "@predicate/interfaces/IPredicateRegistry.sol";

contract DeFiVault is PredicateClient {
    constructor(address _registry, string memory _policy) {
        _initPredicateClient(_registry, _policy);
    }
    
    function withdrawWithLimit(
        address to,
        uint256 amount,
        Attestation calldata attestation
    ) external payable {
        // Encode function details for policy validation
        bytes memory encoded = abi.encodeWithSignature(
            "_executeWithdraw(address,uint256)",
            to,
            amount
        );
        
        // Advanced authorization with full context
        require(
            _authorizeTransaction(attestation, encoded, msg.sender, msg.value),
            "Unauthorized"
        );
        
        _executeWithdraw(to, amount);
    }
}
```

**Benefits:** Complete policy flexibility, function-aware rules, value validation

### Quick Decision Guide

**The key question: "Do I need to enforce different rules based on WHAT users are doing, or just WHO is doing it?"**

If you answered "just WHO", use BasicPredicateClient - it's simpler, cheaper, and covers most use cases.

| Question | BasicPredicateClient | PredicateClient |
|----------|---------------------|-----------------|
| Need to validate WHO can call? | ✅ | ✅ |
| Need to validate WHEN they can call? | ✅ | ✅ |
| Need to validate WHICH function? | ❌ | ✅ |
| Need to validate HOW MUCH value? | ❌ | ✅ |
| Need to validate function PARAMETERS? | ❌ | ✅ |

See `src/examples/inheritance/` for complete working examples.

## Integration Patterns

Predicate v2 supports multiple integration patterns:

### 1. Inheritance Pattern (Recommended for most use cases)
- **Location**: `src/examples/inheritance/`
- **Best for**: Direct control, minimal dependencies
- Contract directly inherits `PredicateClient`
- Lowest gas cost, most straightforward

### 2. Proxy Pattern (Recommended for separation of concerns)
- **Location**: `src/examples/proxy/`
- **Best for**: Clean separation, upgradeability
- Separate proxy contract handles validation
- Business logic contract remains simple

See [src/examples/README.md](./src/examples/README.md) for detailed pattern documentation.

## Architecture

- **PredicateRegistry**: Core registry managing attesters, policies, and validation
- **PredicateClient**: Mixin contract for customer integration  
- **Statement**: Data structure representing a transaction to be validated
- **Attestation**: Signed approval from an authorized attester

```
User Transaction
     ↓
Your Contract (with PredicateClient)
     ↓
_authorizeTransaction()
     ↓
PredicateRegistry.validateAttestation()
     ↓
Verify signature & policy
     ↓
Execute business logic
```

## Key Concepts

### Statement (formerly Task)
A `Statement` represents a claim about a transaction to be executed:
- UUID for replay protection
- Transaction parameters (sender, target, value, encoded function call)
- Policy identifier
- Expiration timestamp

### Attestation
An `Attestation` is a signed approval from an authorized attester:
- Matching UUID from the statement
- Attester address
- ECDSA signature over the statement hash
- Expiration timestamp

### Events for Monitoring

Predicate v2 emits comprehensive events for off-chain monitoring:

**PredicateRegistry events:**
- `AttesterRegistered` / `AttesterDeregistered` - Attester management
- `PolicySet` - Policy changes (emitted when client calls `setPolicyID()`)
- `StatementValidated` - Successful attestation validations

**PredicateClient events** (from your contract):
- `PredicatePolicyIDUpdated` - Track policy changes in your contract
- `PredicateRegistryUpdated` - Alert on registry address changes (security-critical)

**Note:** Transaction authorization is tracked via `StatementValidated` from PredicateRegistry (no duplicate event needed).

These events enable:
- 📊 Analytics and usage tracking
- 🔍 Audit trails and compliance monitoring
- ⚠️ Security alerts (unexpected policy/registry changes)
- 🐛 Debugging and transaction analysis

## Migration from v1

v2 introduces several improvements over v1:

| Feature | v1 | v2 |
|---------|----|----|
| Architecture | Multiple ServiceManager components | Single PredicateRegistry |
| Validation | Quorum-based | Single attester signature |
| Policies | Complex objects | Simple string identifiers |
| Replay Protection | Block-based nonces | UUID-based with expiration |
| Client Integration | Direct calls | PredicateClient mixin |

See [OVERVIEW.md](./OVERVIEW.md#migration-guide-for-v1--v2) for detailed migration guide.

## Installation

This repository depends on some submodules. Please run the following command before testing. 

```bash
git submodule update --init --recursive
```

### Foundry 

```shell
$ forge install PredicateLabs/predicate-contracts 
```

### Node

```bash
npm install @predicate/predicate-contracts
```


## Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Cast

```shell
$ cast <subcommand>
```

## Documentation

- **[OVERVIEW.md](./OVERVIEW.md)** - Complete technical overview of v2 architecture
- **[PLAN.md](./PLAN.md)** - Pre-deployment checklist and task tracking
- **[src/examples/README.md](./src/examples/README.md)** - Integration patterns guide
- **[src/examples/](./src/examples/)** - Working code examples

## Contributing

Contributions are welcome! Please ensure:
- All tests pass: `forge test`
- Code is formatted: `forge fmt`
- Changes are documented

## License

See [LICENSE](./LICENSE) for details.

## Disclaimer 

This library is provided as-is, without any guarantees or warranties. Use at your own risk.
