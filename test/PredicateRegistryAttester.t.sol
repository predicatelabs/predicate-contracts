// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {PredicateRegistry} from "../src/PredicateRegistry.sol";
import {Statement, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract PredicateRegistryAttesterTest is PredicateRegistrySetup {
    // extra attester
    address attesterThree;
    uint256 attesterThreePk;

    function setUp() public override {
        super.setUp();
        (attesterThree, attesterThreePk) = makeAddrAndKey("attesterThree");
    }

    //attester tests
    function testIsAttesterRegistered() public {
        assertTrue(predicateRegistry.isAttesterRegistered(attesterOne));
        assertTrue(predicateRegistry.isAttesterRegistered(attesterTwo));

        assertFalse(predicateRegistry.isAttesterRegistered(attesterThree));
    }

    function testRegisteredAttesters() public {
        address[] memory registeredAttesters = predicateRegistry.getRegisteredAttesters();
        assertEq(registeredAttesters.length, 2);
        assertEq(registeredAttesters[0], attesterOne);
        assertEq(registeredAttesters[1], attesterTwo);
    }

    function testOwnerCanRegisterAttester() public {
        vm.prank(owner);
        predicateRegistry.registerAttester(attesterThree);
        assertTrue(predicateRegistry.isAttesterRegistered(attesterThree));
        assertEq(predicateRegistry.getRegisteredAttesters().length, 3);
        assertEq(predicateRegistry.getRegisteredAttesters()[2], attesterThree);
    }

    function testCannotRegisterAttesterThatIsAlreadyRegistered() public {
        vm.expectRevert("Predicate.registerAttester: attester already registered");
        vm.prank(owner);
        predicateRegistry.registerAttester(attesterOne);
    }

    function testOwnerCanDeregisterAttester() public {
        assertTrue(predicateRegistry.isAttesterRegistered(attesterOne));

        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterOne);
        assertFalse(predicateRegistry.isAttesterRegistered(attesterOne));
        assertEq(predicateRegistry.getRegisteredAttesters().length, 1);
        assertEq(predicateRegistry.getRegisteredAttesters()[0], attesterTwo);
    }

    function testCannotDeregisterAttesterThatIsNotRegistered() public {
        vm.expectRevert("Predicate.deregisterAttester: attester not registered");
        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterThree);
    }

    function testRandomAddrCannotRegisterAttester() public {
        vm.prank(randomAddress);
        vm.expectRevert();
        predicateRegistry.registerAttester(attesterOne);
    }

    function testRandomAddrCannotDeregisterAttester() public {
        vm.prank(randomAddress);
        vm.expectRevert();
        predicateRegistry.deregisterAttester(attesterOne);
    }
}
