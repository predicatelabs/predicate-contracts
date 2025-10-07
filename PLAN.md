# Predicate Contracts v2 - Pre-Deployment Plan

This document outlines all changes that should be made before deploying v2 to production.

---

## 📊 Progress Summary

| Task | Status | Commit |
|------|--------|--------|
| 1. Task → Statement rename | ✅ Complete | `86734307` |
| 2. ERC-7201 storage fix | ✅ Complete | `f2c969ec` |
| 3. Wrapper pattern docs | ✅ Complete | `5bb91fcb` |
| 4. Main README update | ✅ Complete | `9e4e4df1` |
| 5. NatSpec documentation | ✅ Complete | `29d583be` |
| BONUS: setPolicy → setPolicyId | ✅ Complete | `4aa38e83` |
| 6. Deployment scripts | ⏸️ **TODO** | - |
| 7. Events in PredicateClient | ⏸️ **TODO** | - |

**Current Branch**: `andy/PRE-2213`
**Tests**: ✅ All 29 passing
**Compilation**: ✅ Clean

---

## 🔴 Critical Changes (Must Complete Before Deploy)

### 1. Rename Task → Statement ✅ **COMPLETED**

**What**: Renamed all references from "Task" to "Statement" for semantic clarity
**Why**: "Task" implies async work; "Statement" correctly represents a claim/assertion about a transaction
**Files**: 6 core contracts + 3 test files + 2 examples
**Key Changes**:
- `struct Task` → `struct Statement`
- `hashTaskWithExpiry()` → `hashStatementWithExpiry()`
- `hashTaskSafe()` → `hashStatementSafe()`
- `TaskValidated` event → `StatementValidated`
- `spentTaskIDs` → `usedStatementUUIDs`

**Result**: ✅ All 29 tests passing | Commit: `86734307`

---

### 2. Fix PredicateProtected Storage Pattern ✅ **COMPLETED**

**What**: Implemented ERC-7201 namespaced storage pattern
**Why**: Prevents storage collisions in upgradeable contracts
**Files**: `src/examples/proxy/PredicateProtected.sol`
**Key Changes**:
- Replaced direct storage variables with `PredicateProtectedStorage` struct
- Implemented `_getPredicateProtectedStorage()` accessor
- Storage slot: `0x5e2f89b9a8b8c33b0c4efeb789eb49ad0c1a074e1e2f1c94e31ab1f8f1e00800`

**Result**: ✅ All 29 tests passing | Commit: `f2c969ec`

---

### 3. Update README.md - Wrapper Pattern Status ✅ **COMPLETED**

**What**: Marked wrapper pattern as "NOT YET IMPLEMENTED"
**Why**: README documented non-existent code, causing confusion
**Files**: `src/examples/README.md`
**Key Changes**:
- Added ⚠️ "NOT YET IMPLEMENTED" warning
- Changed all descriptions to "Planned" tense
- Updated recommendations to suggest Inheritance or Proxy patterns

**Result**: Clear user guidance | Commit: `5bb91fcb`

---

### 4. Update Main README.md ✅ **COMPLETED**

**What**: Enhanced README with comprehensive integration guide
**Why**: Original README was minimal, didn't guide users on integration
**Files**: `README.md`
**Sections Added**:
- Overview, Quick Start (3-step integration), Integration Patterns
- Architecture diagram, Key Concepts, Migration from v1 table
- Documentation links, Contributing guidelines

**Result**: Production-ready user documentation | Commit: `9e4e4df1`

### BONUS: Rename setPolicy → setPolicyId ✅ **COMPLETED**

**What**: Renamed setPolicy/getPolicy to setPolicyId/getPolicyId throughout
**Why**: Clarifies it's an identifier (typically "x-{hash[:16]}") not the full policy
**Files**: All interfaces, implementations, examples, and tests
**Documentation**: Added format examples in NatSpec

**Result**: ✅ All 29 tests passing | Commit: `4aa38e83`

---

## 🟡 Important Changes (Should Complete Before Deploy)

### 5. Add Comprehensive NatSpec Documentation ✅ **COMPLETED**

**What**: Added complete NatSpec documentation to all core contracts
**Why**: Essential for auditors and integrators
**Files**: `PredicateRegistry.sol`, `PredicateClient.sol`, `IPredicateRegistry.sol`
**Documentation Added**:
- Contract-level @title, @author, @notice, @dev
- Function-level @notice, @param, @return for all public functions
- Security considerations with @custom:security tags
- Process flows and usage examples
- ERC-7201 storage pattern explanations

**Result**: ✅ Audit-ready documentation | Commit: `29d583be`

---

### 6. Add Deployment Scripts

**What**: Create deployment scripts for PredicateRegistry
**Why**: Need reproducible deployment process for mainnet and testnets

**Files to Create**:
- [ ] `script/Deploy.s.sol` - Main deployment script
- [ ] `script/DeployTestnet.s.sol` - Testnet-specific script
- [ ] `script/UpgradeRegistry.s.sol` - Upgrade script

**Template**:
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

---

### 7. Add Events to PredicateClient

**What**: Add events for important state changes in PredicateClient
**Why**: Essential for off-chain monitoring and indexing

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

---

## 🟢 Nice-to-Have Changes (Post-Deploy OK)

### 8. Add Gas Optimization Tests

**What**: Benchmark gas costs across different patterns and configurations
**Files**: `test/gas/PredicateRegistryGas.t.sol`
**Tests**: 
- Gas comparison: Inheritance vs Proxy patterns
- Validation costs with different signature/policy lengths
- Benchmark vs v1 if available

---

### 9. Add Integration Tests for Multiple Attesters

**What**: Test realistic multi-attester scenarios
**Files**: `test/integration/MultiAttester.t.sol`
**Scenarios**: Multiple attesters, switching, deregistration, different policies

---

### 10. Add Upgrade Tests

**What**: Verify upgrade path and storage compatibility
**Files**: `test/upgrades/PredicateRegistryUpgrade.t.sol`
**Tests**: State preservation, attester/policy compatibility, storage layout

---

### 11. Create Migration Guide Document

**What**: Detailed v1 → v2 migration guide
**Files**: `MIGRATION.md`
**Content**: Step-by-step migration, code comparisons, breaking changes, FAQ

---

### 12. Add CI/CD Pipeline

**What**: Automate testing and quality checks
**Files**: `.github/workflows/test.yml`, `coverage.yml`, `lint.yml`
**Jobs**: Forge tests, coverage, linting, Slither analysis

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
