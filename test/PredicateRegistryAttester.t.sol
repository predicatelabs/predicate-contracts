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

    function testAttesterIndexMappingAfterRegistration() public {
        assertEq(predicateRegistry.attesterIndex(attesterOne), 0);
        assertEq(predicateRegistry.attesterIndex(attesterTwo), 1);

        vm.prank(owner);
        predicateRegistry.registerAttester(attesterThree);
        assertEq(predicateRegistry.attesterIndex(attesterThree), 2);
    }

    function testAttesterIndexMappingAfterDeregistrationSwap() public {
        vm.prank(owner);
        predicateRegistry.registerAttester(attesterThree);

        address[] memory before = predicateRegistry.getRegisteredAttesters();
        assertEq(before.length, 3);
        assertEq(before[0], attesterOne);
        assertEq(before[1], attesterTwo);
        assertEq(before[2], attesterThree);

        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterOne);

        address[] memory afterDereg = predicateRegistry.getRegisteredAttesters();
        assertEq(afterDereg.length, 2);
        assertEq(afterDereg[0], attesterThree);
        assertEq(afterDereg[1], attesterTwo);

        assertEq(predicateRegistry.attesterIndex(attesterThree), 0);
        assertEq(predicateRegistry.attesterIndex(attesterTwo), 1);
        assertEq(predicateRegistry.attesterIndex(attesterOne), 0);
    }

    function testDeregisterLastAttester() public {
        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterTwo);

        assertEq(predicateRegistry.getRegisteredAttesters().length, 1);
        assertEq(predicateRegistry.getRegisteredAttesters()[0], attesterOne);

        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterOne);

        assertEq(predicateRegistry.getRegisteredAttesters().length, 0);
        assertFalse(predicateRegistry.isAttesterRegistered(attesterOne));
    }

    function testMultipleDeregistrationsInSequence() public {
        address attesterFour = makeAddr("attesterFour");
        address attesterFive = makeAddr("attesterFive");

        vm.prank(owner);
        predicateRegistry.registerAttester(attesterThree);
        vm.prank(owner);
        predicateRegistry.registerAttester(attesterFour);
        vm.prank(owner);
        predicateRegistry.registerAttester(attesterFive);

        address[] memory initial = predicateRegistry.getRegisteredAttesters();
        assertEq(initial.length, 5);

        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterTwo);

        address[] memory afterFirst = predicateRegistry.getRegisteredAttesters();
        assertEq(afterFirst.length, 4);
        assertEq(afterFirst[1], attesterFive);
        assertTrue(predicateRegistry.isAttesterRegistered(attesterFive));

        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterOne);

        address[] memory afterSecond = predicateRegistry.getRegisteredAttesters();
        assertEq(afterSecond.length, 3);
        assertTrue(predicateRegistry.isAttesterRegistered(attesterThree));
        assertTrue(predicateRegistry.isAttesterRegistered(attesterFour));
        assertTrue(predicateRegistry.isAttesterRegistered(attesterFive));
        assertFalse(predicateRegistry.isAttesterRegistered(attesterOne));
        assertFalse(predicateRegistry.isAttesterRegistered(attesterTwo));

        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterThree);

        address[] memory afterThird = predicateRegistry.getRegisteredAttesters();
        assertEq(afterThird.length, 2);
        assertTrue(predicateRegistry.isAttesterRegistered(attesterFour));
        assertTrue(predicateRegistry.isAttesterRegistered(attesterFive));
        assertFalse(predicateRegistry.isAttesterRegistered(attesterThree));
    }

    function testIndexMappingDeletedAfterDeregistration() public {
        assertEq(predicateRegistry.attesterIndex(attesterOne), 0);
        assertTrue(predicateRegistry.isAttesterRegistered(attesterOne));

        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterOne);

        assertFalse(predicateRegistry.isAttesterRegistered(attesterOne));
    }

    function testReRegisterAfterDeregistration() public {
        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterOne);

        assertEq(predicateRegistry.getRegisteredAttesters().length, 1);

        vm.prank(owner);
        predicateRegistry.registerAttester(attesterOne);

        assertTrue(predicateRegistry.isAttesterRegistered(attesterOne));
        assertEq(predicateRegistry.getRegisteredAttesters().length, 2);
        assertEq(predicateRegistry.attesterIndex(attesterOne), 1);
    }
}
