// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {PredicateRegistry} from "../src/PredicateRegistry.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract PredicateRegistryPolicyTest is PredicateRegistrySetup {
    // extra policy
    string policyThree = "policyThree";
    string randomPolicy = "randomPolicy";

    //policy tests
    function testIsPolicyEnabled() public {
        assertTrue(predicateRegistry.isPolicyEnabled(policyOne));
        assertTrue(predicateRegistry.isPolicyEnabled(policyTwo));

        assertFalse(predicateRegistry.isPolicyEnabled(randomPolicy));
    }

    function testEnabledPolicies() public {
        string[] memory enabledPolicies = predicateRegistry.enabledPolicies();
        assertEq(enabledPolicies.length, 2);
        assertEq(enabledPolicies[0], policyOne);
        assertEq(enabledPolicies[1], policyTwo);
    }

    function testOwnerCanEnablePolicy() public {
        assertFalse(predicateRegistry.isPolicyEnabled(policyThree));

        vm.prank(owner);
        predicateRegistry.enablePolicy(policyThree);
        assertTrue(predicateRegistry.isPolicyEnabled(policyThree));
    }

    function testOwnerCanDisablePolicy() public {
        assertTrue(predicateRegistry.isPolicyEnabled(policyOne));

        vm.prank(owner);
        predicateRegistry.disablePolicy(policyOne);
        assertEq(predicateRegistry.enabledPolicies().length, 1);
        assertEq(predicateRegistry.enabledPolicies()[0], policyTwo);
    }

    function testCannotDisablePolicyThatDoesNotExist() public {
        vm.expectRevert("Predicate.disablePolicy: policy doesn't exist");
        vm.prank(owner);
        predicateRegistry.disablePolicy(randomPolicy);
    }

    function testCannotEnableEmptyPolicyString() public {
        vm.expectRevert("Predicate.enablePolicy: policy string cannot be empty");
        vm.prank(owner);
        predicateRegistry.enablePolicy("");
    }

    function testCannotEnableDuplicatePolicy() public {
        vm.expectRevert("Predicate.enablePolicy: policy already exists");
        vm.prank(owner);
        predicateRegistry.enablePolicy(policyOne);
    }

    function testRandomAddrCannotEnablePolicy() public {
        vm.prank(randomAddress);
        vm.expectRevert();
        predicateRegistry.enablePolicy(policyOne);
    }
    
    function testRandomAddrCannotDisablePolicy() public {
        vm.prank(randomAddress);
        vm.expectRevert();
        predicateRegistry.disablePolicy(policyOne);
    }

    function testOwnerCanOverrideClientPolicy() public {
        assertEq(predicateRegistry.getPolicy(address(this)), "");

        vm.prank(owner);
        predicateRegistry.overrideClientPolicy(policyOne, address(this));
        assertEq(predicateRegistry.getPolicy(address(this)), policyOne);
    }

    function testOwnerCannotOverrideClientPolicyToSamePolicy() public {
        vm.prank(owner);
        predicateRegistry.overrideClientPolicy(policyOne, address(this));
        assertEq(predicateRegistry.getPolicy(address(this)), policyOne);

        vm.expectRevert("Predicate.overrideClientPolicy: client already has this policy");
        vm.prank(owner);
        predicateRegistry.overrideClientPolicy(policyOne, address(this));
    }

    function testOwnerCannotOverrideClientPolicyToDisabledPolicy() public {
        vm.prank(owner);
        predicateRegistry.disablePolicy(policyOne);

        vm.expectRevert("Predicate.overrideClientPolicy: policy doesn't exist");
        vm.prank(owner);
        predicateRegistry.overrideClientPolicy(policyOne, address(this));
    }
}
