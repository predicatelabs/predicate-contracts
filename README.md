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

### For Smart Contract Developers

Integrate Predicate validation into your contract in 3 steps:

```solidity
// 1. Import and inherit PredicateClient
import {PredicateClient} from "@predicate/mixins/PredicateClient.sol";
import {Attestation} from "@predicate/interfaces/IPredicateRegistry.sol";

contract MyContract is PredicateClient {
    
    // 2. Initialize in constructor
    constructor(address _registry, string memory _policy) {
        _initPredicateClient(_registry, _policy);
    }
    
    // 3. Add attestation parameter and validate
    function protectedFunction(
        address recipient,
        uint256 amount,
        Attestation calldata _attestation  // Add this
    ) external payable {
        // Encode the internal function call
        bytes memory encodedSigAndArgs = abi.encodeWithSignature(
            "_internalFunction(address,uint256)", 
            recipient, 
            amount
        );
        
        // Validate the attestation
        require(
            _authorizeTransaction(_attestation, encodedSigAndArgs, msg.sender, msg.value),
            "MyContract: unauthorized transaction"
        );
        
        // Execute business logic
        _internalFunction(recipient, amount);
    }
    
    function _internalFunction(address recipient, uint256 amount) internal {
        // Your business logic here
    }
}
```

See `src/examples/` for complete working examples.

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
- `PolicySet` - Policy changes (emitted when client calls `setPolicyId()`)
- `StatementValidated` - Successful attestation validations

**PredicateClient events** (from your contract):
- `PredicatePolicyIdUpdated` - Track policy changes in your contract
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