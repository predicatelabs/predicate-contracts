# predicate-contracts
Predicate is programmable policy infrastructure for onchain financial products in regulated markets. It allows developers to enforce custom compliance rules at the smart contract level. This repository holds the official solidity contracts for [Predicate's](https://predicate.io) Application Compliance offering. 

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
├── mixins/
│   └── PredicateClient.sol     # Inherit this in your contracts
│                               # - _initPredicateClient() for setup
│                               # - _authorizeTransaction() for validation
│                               # - ERC-7201 namespaced storage
│
├── interfaces/
│   ├── IPredicateRegistry.sol  # Registry interface + Statement/Attestation structs
│   └── IPredicateClient.sol    # Client interface
│
└── examples/                   # Reference implementations
    ├── inheritance/            # Direct inheritance pattern
    └── proxy/                  # Proxy pattern for separation of concerns
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

- **Integration Guide:** [docs.predicate.io/v2/applications/smart-contracts](https://docs.predicate.io/v2/applications/smart-contracts)
- **Supported Chains:** [docs.predicate.io/v2/applications/supported-chains](https://docs.predicate.io/v2/applications/supported-chains)
- **API Reference:** [docs.predicate.io/api-reference](https://docs.predicate.io/api-reference/introduction)

## License

See [LICENSE](./LICENSE) for details.

## Disclaimer

This software is provided as-is. Use at your own risk.
