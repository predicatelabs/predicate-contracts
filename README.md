# predicate-contracts
Predicate is programmable policy infrastructure for onchain financial products in regulated markets. It allows developers to enforce custom compliance rules at the smart contract level. This repository holds the official solidity contracts for [Predicate's](https://predicate.io) Application Compliance and Asset Compliance offerings. 

## How It Works

![Predicate Application Compliance Flow](https://raw.githubusercontent.com/PredicateLabs/predicate-contracts/main/images/system.png)

**Full integration guide:** [docs.predicate.io](https://docs.predicate.io/v2/applications/smart-contracts)

## Repository Structure

```
src/
├── PredicateRegistry.sol       # Core registry contract (Predicate-owned)
│                               # - Attester management
│                               # - Attestation verification
│                               # - UUID-based replay protection
│
├── Freezable.sol               # Abstract contract for account freezing (Asset Compliance)
│                               # - Role-based freeze management
│                               # - ERC-7201 namespaced storage
│
├── mixins/
│   ├── PredicateClient.sol     # Full-featured client (WHO + WHAT validation)
│   │                           # - _authorizeTransaction(attestation, encoded, sender, value)
│   │
│   └── BasicPredicateClient.sol # Simplified client (WHO-only validation)
│                               # - _authorizeTransaction(attestation, sender)
│                               # - Use when policies only validate sender identity
│
├── interfaces/
│   ├── IPredicateRegistry.sol  # Registry interface + Statement/Attestation structs
│   ├── IPredicateClient.sol    # Client interface
│   └── IFreezable.sol          # Freezable interface for Asset Compliance
│
└── examples/                   # Reference implementations
    ├── inheritance/            # Direct inheritance pattern (Application Compliance)
    ├── proxy/                  # Proxy pattern for separation of concerns
    └── asset-compliance/       # Asset Compliance pattern (account freezing)
```

## Installation

### Foundry

```bash
forge install PredicateLabs/predicate-contracts
```

### npm

```bash
npm install @predicate/contracts
```

## Quick Example

**BasicPredicateClient** - Use when your policy only validates WHO is calling (sender identity):

```solidity
import {BasicPredicateClient} from "@predicate/contracts/src/mixins/BasicPredicateClient.sol";
import {Attestation} from "@predicate/contracts/src/interfaces/IPredicateRegistry.sol";

contract MyVault is BasicPredicateClient {
    constructor(address _registry, string memory _policyID) {
        _initPredicateClient(_registry, _policyID);
    }

    function deposit(uint256 amount, Attestation calldata attestation) external payable {
        require(_authorizeTransaction(attestation, msg.sender), "Unauthorized");
        // ... business logic
    }
}
```

**PredicateClient** - Use when your policy also validates WHAT is being done (function, args, value):

```solidity
import {PredicateClient} from "@predicate/contracts/src/mixins/PredicateClient.sol";
import {Attestation} from "@predicate/contracts/src/interfaces/IPredicateRegistry.sol";

contract MyVault is PredicateClient {
    constructor(address _registry, string memory _policyID) {
        _initPredicateClient(_registry, _policyID);
    }

    function deposit(uint256 amount, Attestation calldata attestation) external payable {
        bytes memory encoded = abi.encodeWithSignature("_deposit(uint256)", amount);
        require(_authorizeTransaction(attestation, encoded, msg.sender, msg.value), "Unauthorized");
        // ... business logic
    }
}
```

## Documentation

- **Application Compliance:** [docs.predicate.io/v2/applications/smart-contracts](https://docs.predicate.io/v2/applications/smart-contracts)
- **Asset Compliance:** [docs.predicate.io/v2/assets/overview](https://docs.predicate.io/v2/assets/overview)
- **Supported Chains:** [docs.predicate.io/v2/applications/supported-chains](https://docs.predicate.io/v2/applications/supported-chains)
- **API Reference:** [docs.predicate.io/api-reference](https://docs.predicate.io/api-reference/introduction)

## License

See [LICENSE](./LICENSE) for details.

## Disclaimer

This software is provided as-is. Use at your own risk.
