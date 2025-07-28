// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {PredicateRegistry} from "../src/PredicateRegistry.sol";
import {Task, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract PredicateRegistryAttestorTest is PredicateRegistrySetup {
    // extra attestor
    address attestorThree;
    uint256 attestorThreePk;

    function setUp() public override {
        super.setUp();
        (attestorThree, attestorThreePk) = makeAddrAndKey("attestorThree");
    }

    //attestor tests
    function testIsAttestorRegistered() public {
        assertTrue(predicateRegistry.isAttestorRegistered(attestorOne));
        assertTrue(predicateRegistry.isAttestorRegistered(attestorTwo));

        assertFalse(predicateRegistry.isAttestorRegistered(attestorThree));
    }

    function testRegisteredAttestors() public {
        address[] memory registeredAttestors = predicateRegistry.getRegisteredAttestors();
        assertEq(registeredAttestors.length, 2);
        assertEq(registeredAttestors[0], attestorOne);
        assertEq(registeredAttestors[1], attestorTwo);
    }

    function testOwnerCanRegisterAttestor() public {
        vm.prank(owner);
        predicateRegistry.registerAttestor(attestorThree);
        assertTrue(predicateRegistry.isAttestorRegistered(attestorThree));
        assertEq(predicateRegistry.getRegisteredAttestors().length, 3);
        assertEq(predicateRegistry.getRegisteredAttestors()[2], attestorThree);
    }

    function testCannotRegisterAttestorThatIsAlreadyRegistered() public {
        vm.expectRevert("Predicate.registerAttestor: attestor already registered");
        vm.prank(owner);
        predicateRegistry.registerAttestor(attestorOne);
    }

    function testOwnerCanDeregisterAttestor() public {
        assertTrue(predicateRegistry.isAttestorRegistered(attestorOne));

        vm.prank(owner);
        predicateRegistry.deregisterAttestor(attestorOne);
        assertFalse(predicateRegistry.isAttestorRegistered(attestorOne));
        assertEq(predicateRegistry.getRegisteredAttestors().length, 1);
        assertEq(predicateRegistry.getRegisteredAttestors()[0], attestorTwo);
    }

    function testCannotDeregisterAttestorThatIsNotRegistered() public {
        vm.expectRevert("Predicate.deregisterAttestor: attestor not registered");
        vm.prank(owner);
        predicateRegistry.deregisterAttestor(attestorThree);
    }

    function testRandomAddrCannotRegisterAttestor() public {
        vm.prank(randomAddress);
        vm.expectRevert();
        predicateRegistry.registerAttestor(attestorOne);
    }

    function testRandomAddrCannotDeregisterAttestor() public {
        vm.prank(randomAddress);
        vm.expectRevert();
        predicateRegistry.deregisterAttestor(attestorOne);
    }
}
