# Predicate Contract Integration Examples

This directory contains example implementations demonstrating different patterns for integrating Predicate in your smart contracts. Each pattern offers a different approach with its own trade-offs in terms of complexity, gas efficiency, and modularity.

## Integration Patterns Diagram

![Integration Patterns](./integration-patterns.png)

The diagram above illustrates the three integration patterns and their interaction flows:
- **Proxy Pattern**: Uses a dedicated PredicateProxy contract as an intermediary
- **Inheritance Pattern**: Business logic directly inherits PredicateClient functionality
- **Wrapper Pattern**: Business logic calls an external PredicateWrapper contract

## Base Contract: MetaCoin

All examples use a simple `MetaCoin` contract as the base implementation. The original contract features:
- A simple token with balances
- Basic transfer functionality 
- Balance checking

## Example Patterns

### 1. Proxy Pattern

**Location:** `src/examples/proxy/`

The Proxy pattern uses a dedicated proxy contract to interact with the main contract on behalf of users.

**Key components:**
- `PredicateClientProxy.sol`: Acts as an intermediary between users and the protected contract
- `PredicateProtected.sol`: Base contract with proxy-related functionality
- `IPredicateProtected.sol`: Interface defining the proxy protection methods
- `MetaCoin.sol`: Main contract with proxy integration

**How it works:**
1. Users interact with the proxy contract instead of directly with the main contract
2. The proxy validates transactions through Predicate before forwarding them
3. The main contract checks that calls come only from the authorized proxy

**Benefits:**
- Clean separation of concerns
- Upgradable validation logic
- Original contract interface remains unchanged to external callers

**Drawbacks:**
- Additional gas costs for proxy deployment and calls
- More complex architecture

### 2. Wrapper Pattern

**Location:** `src/examples/wrapper/`

The Wrapper pattern uses a modifier-based approach to wrap protected functions with Predicate validation by calling an external contract.

**Key components:**
- `PredicateClientWrapper.sol`: External contract that provides the validation functionality
- `PredicateProtected.sol`: Base contract with wrapper-related functionality
- `IPredicateProtected.sol`: Interface for wrapper methods
- `MetaCoin.sol`: Main contract with wrapper integration

**How it works:**
1. Protected functions are decorated with a validation modifier
2. The modifier makes an external call to the PredicateClientWrapper contract for validation
3. The external wrapper contract performs Predicate validation before allowing execution to continue
4. If validation fails, the transaction is reverted

**Benefits:**
- Flexible per-function protection
- Validation logic can be upgraded by changing the external wrapper contract

**Drawbacks:**
- Requires modifying function signatures to include Predicate message
- Protected and unprotected functions coexist, which might lead to confusion
- External calls can increase gas costs
- Introduces dependency on an external contract

### 3. Inheritance Pattern

**Location:** `src/examples/inheritance/`

The Inheritance pattern directly extends the Predicate client functionality through inheritance.

**Key components:**
- `MetaCoin.sol`: Inherits from `PredicateClient` to gain validation capabilities

**How it works:**
1. The contract inherits from `PredicateClient`
2. Protected functions manually call validation methods
3. Business logic is executed only if validation passes

**Benefits:**
- Most direct integration
- Full control over validation flow
- No additional contracts required

**Drawbacks:**
- Tighter coupling between business logic and Predicate validation
- Requires more manual validation code
- May be harder to upgrade validation logic

## Choosing the Right Pattern

- **Use the Proxy pattern** when you need a clean separation of concerns and potentially upgradable validation logic. This is the recommended approach.
- **Use the Wrapper pattern** when we need to call the business logic contract first.
- **Use the Inheritance pattern** when you need direct control over the validation process and want to minimize contract dependencies.

Each pattern can be adapted to suit your specific needs and security requirements.