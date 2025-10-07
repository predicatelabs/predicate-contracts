# Predicate Contracts v2 - Pre-Deployment Plan

This document outlines all changes that should be made before deploying v2 to production.

---

## 🔴 Critical Changes (Must Complete)

### 1. Rename Task → Statement ✅ **COMPLETED**

**Rationale**: The current naming "Task" implies an asynchronous work item, but the struct actually represents a "Statement" - a claim or assertion about a transaction that gets attested to. This rename improves semantic clarity.

**Files to Update**:

#### Core Contracts:
- [x] `src/interfaces/IPredicateRegistry.sol`
  - Rename `struct Task` → `struct Statement`
  - Update function parameter: `Task memory _task` → `Statement memory _statement`
  
- [x] `src/PredicateRegistry.sol`
  - Update import: `Task` → `Statement`
  - Rename function: `hashTaskWithExpiry(Task calldata _task)` → `hashStatementWithExpiry(Statement calldata _statement)`
  - Rename function: `hashTaskSafe(Task calldata _task)` → `hashStatementSafe(Statement calldata _statement)`
  - Update function: `validateAttestation(Task calldata _task, ...)` → `validateAttestation(Statement calldata _statement, ...)`
  - Rename event: `TaskValidated` → `StatementValidated`
  - Rename storage: `mapping(string => bool) public spentTaskIDs` → `mapping(string => bool) public usedStatementUUIDs`
  - Update all internal variable names: `_task` → `_statement`

- [x] `src/mixins/PredicateClient.sol`
  - Update import: `Task` → `Statement`
  - Update internal variable: `Task memory task` → `Statement memory statement`

#### Test Files:
- [x] `test/PredicateRegistryAttestation.t.sol`
  - Update all `Task` references to `Statement`
  - Update variable names

- [x] `test/Client.t.sol`
  - Update all `Task` references to `Statement`
  - Update variable names

- [x] `test/PredicateRegistryAttester.t.sol`
  - Update import

- [x] `test/helpers/PredicateRegistrySetup.sol`
  - No changes needed (imports from core)

#### Examples:
- [x] `src/examples/inheritance/MetaCoin.sol` - No direct changes needed (uses imports)
- [x] `src/examples/proxy/PredicateClientProxy.sol` - No direct changes needed (uses imports)
- [x] `src/examples/proxy/MetaCoin.sol` - No changes needed

**Actual Effort**: ~1.5 hours
**Tests**: ✅ All 29 tests passing

---

### 2. Fix PredicateProtected Storage Pattern ✅ **COMPLETED**

**Rationale**: Current implementation uses regular storage which can cause collisions in upgradeable contracts. Should use ERC-7201 namespaced storage like PredicateClient does.

**File to Update**:
- [x] `src/examples/proxy/PredicateProtected.sol`

**Changes Needed**:

```solidity
// CURRENT (Line 8-10):
bool private _predicateProxyEnabled;
PredicateClientProxy private _predicateProxy;

// SHOULD BE:
struct PredicateProtectedStorage {
    bool predicateProxyEnabled;
    PredicateClientProxy predicateProxy;
}

bytes32 private constant _PREDICATE_PROTECTED_STORAGE_SLOT = 
    0x[calculated_slot]; // Calculate using keccak256

function _getPredicateProtectedStorage() private pure returns (PredicateProtectedStorage storage $) {
    assembly {
        $.slot := _PREDICATE_PROTECTED_STORAGE_SLOT
    }
}
```

**Storage Slot Calculation**:
```javascript
// Calculate: keccak256(abi.encode(uint256(keccak256("predicate.storage.PredicateProtected")) - 1)) & ~bytes32(uint256(0xff))
```

**Actual Effort**: ~30 minutes
**Storage Slot Used**: `0x5e2f89b9a8b8c33b0c4efeb789eb49ad0c1a074e1e2f1c94e31ab1f8f1e00800`
**Tests**: ✅ All 29 tests passing

---

### 3. Update README.md - Wrapper Pattern Status ✅ **COMPLETED**

**Rationale**: README documents a wrapper pattern that doesn't exist in the codebase, causing confusion.

**File to Update**:
- [x] `src/examples/README.md` - Updated "Choosing the Right Pattern" section
- [x] `src/examples/README.md` - Updated Wrapper pattern section (lines 49-73) to mark as "NOT YET IMPLEMENTED"

**Changes Made**:
- ✅ Marked section as "⚠️ Status: NOT YET IMPLEMENTED"
- ✅ Changed all descriptions to "Planned" tense
- ✅ Added note directing users to contact team or use other patterns
- ✅ Updated "Choosing the Right Pattern" to recommend Inheritance or Proxy patterns
- ✅ Crossed out Wrapper pattern recommendation

**Actual Effort**: 20 minutes

---

### 4. Update Main README.md ✅ **COMPLETED**

**Rationale**: Main README is minimal and doesn't guide users on how to integrate.

**File to Update**:
- [x] `README.md`

**Sections Added**:
- ✅ Overview section with v2 features
- ✅ Quick Start with complete code example
- ✅ Integration Patterns (Inheritance and Proxy)
- ✅ Architecture diagram and explanation
- ✅ Key Concepts (Statement and Attestation)
- ✅ Migration from v1 comparison table
- ✅ Documentation links section
- ✅ Contributing guidelines

**Actual Effort**: 45 minutes

---

## 🟡 Important Changes (Should Complete)

### 5. Add Comprehensive NatSpec Documentation ✅ **COMPLETED**

**Rationale**: Production contracts should have complete documentation for auditors and integrators.

**Files to Update**:
- [x] `src/PredicateRegistry.sol`
  - Added detailed @notice, @param, @return for all functions
  - Documented security considerations with @custom:security tags
  - Explained validation flow step-by-step

- [x] `src/mixins/PredicateClient.sol`
  - Documented ERC-7201 storage pattern
  - Explained authorization flow with process steps
  - Added complete usage example in contract-level docs

- [x] `src/interfaces/IPredicateRegistry.sol`
  - Complete interface documentation
  - Documented expected behavior and security considerations
  - Added @custom tags for Statement and Attestation structs

**Example**:
```solidity
/**
 * @notice Validates an attestation against a statement to authorize a transaction
 * @dev This function verifies:
 *      - Attestation has not expired
 *      - Statement UUID has not been previously used (replay protection)
 *      - UUID and expiration match between statement and attestation
 *      - Signature is valid and from a registered attester
 * @param _statement The statement describing the transaction to be authorized
 * @param _attestation The attester's signed approval of the statement
 * @return isVerified True if validation succeeds, reverts otherwise
 * @custom:security This function marks the UUID as spent to prevent replay attacks
 */
function validateAttestation(
    Statement calldata _statement,
    Attestation calldata _attestation
) external returns (bool isVerified)
```

**Actual Effort**: 2.5 hours
**Tests**: ✅ All 29 tests passing
**Compilation**: ✅ Clean

---

### 6. Add Deployment Scripts

**Rationale**: Need reproducible deployment process.

**Files to Create**:
- [ ] `script/Deploy.s.sol` - Foundry deployment script
- [ ] `script/DeployTestnet.s.sol` - Testnet-specific script
- [ ] `script/UpgradeRegistry.s.sol` - Upgrade script for registry

**Example Template**:
```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";
import {PredicateRegistry} from "../src/PredicateRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy implementation
        PredicateRegistry implementation = new PredicateRegistry();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            PredicateRegistry.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        
        vm.stopBroadcast();
        
        console.log("Implementation:", address(implementation));
        console.log("Proxy:", address(proxy));
    }
}
```

**Estimated Effort**: 2-3 hours

---

### 7. Add Events to PredicateClient

**Rationale**: Important state changes should emit events for off-chain monitoring.

**File to Update**:
- [ ] `src/mixins/PredicateClient.sol`

**Events to Add**:
```solidity
event PredicateRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
event PredicatePolicyUpdated(string oldPolicy, string newPolicy);
event TransactionAuthorized(
    address indexed sender,
    bytes encodedSigAndArgs,
    string attestationUUID,
    address indexed attester
);
```

**Estimated Effort**: 1 hour

---

## 🟢 Nice-to-Have Changes

### 8. Add Gas Optimization Tests

**File to Create**:
- [ ] `test/gas/PredicateRegistryGas.t.sol`

**Tests to Add**:
- Gas cost comparison between patterns (inheritance vs proxy)
- Gas cost for validation with different signature lengths
- Gas cost for different policy string lengths
- Benchmark against v1 if available

**Estimated Effort**: 2-3 hours

---

### 9. Add Integration Tests for Multiple Attesters

**Rationale**: Test realistic scenarios with multiple registered attesters.

**File to Create**:
- [ ] `test/integration/MultiAttester.t.sol`

**Scenarios to Test**:
- Multiple attesters registered
- Switching between attesters
- Attester deregistration doesn't affect others
- Different policies per client

**Estimated Effort**: 2 hours

---

### 10. Add Upgrade Tests

**Rationale**: Verify upgrade path works correctly.

**File to Create**:
- [ ] `test/upgrades/PredicateRegistryUpgrade.t.sol`

**Tests to Add**:
- Upgrade preserves state
- Old attesters still work after upgrade
- Old policies still work after upgrade
- Storage layout compatibility

**Estimated Effort**: 2-3 hours

---

### 11. Create Migration Guide Document

**File to Create**:
- [ ] `MIGRATION.md`

**Content**:
- Detailed step-by-step migration from v1
- Code comparison (before/after)
- Breaking changes list
- Timeline and support information
- FAQ section

**Estimated Effort**: 2-3 hours

---

### 12. Add CI/CD Pipeline

**Files to Create**:
- [ ] `.github/workflows/test.yml`
- [ ] `.github/workflows/coverage.yml`
- [ ] `.github/workflows/lint.yml`

**Jobs to Add**:
- Run forge tests on push
- Run forge coverage and upload to Codecov
- Run solhint for linting
- Run slither for security analysis (if appropriate)

**Estimated Effort**: 2-3 hours

---

## Summary & Timeline

### Critical Path (Must Complete Before Deploy)
1. ✅ Task → Statement rename (2-3 hours)
2. ✅ Fix PredicateProtected storage (1-2 hours)
3. ✅ Update README for wrapper pattern (30 mins)
4. ✅ Update main README (1 hour)
5. ✅ Add NatSpec documentation (3-4 hours)
6. ✅ Add deployment scripts (2-3 hours)

**Total Critical Path**: ~10-14 hours

### Important Changes (Strongly Recommended)
7. Add events to PredicateClient (1 hour)
8. Add gas optimization tests (2-3 hours)
9. Add integration tests (2 hours)
10. Add upgrade tests (2-3 hours)

**Total Important**: ~7-9 hours

### Nice-to-Have (Post-Deploy OK)
11. Create migration guide (2-3 hours)
12. Add CI/CD pipeline (2-3 hours)

**Total Nice-to-Have**: ~4-6 hours

---

## Pre-Deployment Checklist

Before deploying to production, verify:

- [ ] All critical changes completed
- [ ] All tests passing (`forge test`)
- [ ] Gas snapshots reviewed (`forge snapshot`)
- [ ] Code coverage >80% (`forge coverage`)
- [ ] Solidity linter passing
- [ ] Security audit scheduled or completed
- [ ] Deployment scripts tested on testnet
- [ ] Documentation reviewed and approved
- [ ] Example contracts verified and working
- [ ] Migration guide published (if applicable)
- [ ] Monitoring/indexing setup for events
- [ ] Emergency pause mechanism reviewed (if applicable)
- [ ] Owner/admin keys secured with multisig
- [ ] Upgrade path tested and documented

---

## Post-Deployment Tasks

After successful deployment:

1. [ ] Verify contracts on Etherscan/block explorer
2. [ ] Publish package to npm
3. [ ] Update documentation with deployed addresses
4. [ ] Announce deployment and migration timeline
5. [ ] Monitor initial transactions
6. [ ] Set up alerting for critical events
7. [ ] Create runbook for common operations
8. [ ] Train support team on common issues

---

## Rollback Plan

In case of critical issues post-deployment:

1. **If using proxy**: Upgrade to emergency pause implementation
2. **If not using proxy**: Deploy fixed version and migrate
3. **Communication**: Notify all integrators immediately
4. **Documentation**: Update docs with known issues
5. **Timeline**: Provide clear timeline for fix

---

## Questions to Resolve

Before starting implementation, clarify:

1. **Upgradeability**: Is PredicateRegistry deployed as upgradeable proxy?
2. **Attester Onboarding**: What's the process for registering new attesters?
3. **Policy Format**: What's the expected format for policy strings (URLs, IPFS CIDs)?
4. **Network**: Which networks for initial deployment?
5. **Governance**: Who controls the owner key? Multisig details?
6. **Audit**: Is security audit scheduled? Which firm?
7. **Timeline**: Hard deadline for deployment?
8. **Wrapper Pattern**: Should we implement it or officially deprecate it?

---

## Contact & Resources

- **Technical Lead**: [Name]
- **Security Contact**: [Name]
- **Documentation**: See `OVERVIEW.md`
- **Examples**: See `src/examples/`
- **Issues**: [GitHub Issues Link]

