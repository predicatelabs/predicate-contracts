// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockClient} from "./helpers/mocks/MockClient.sol";
import "./helpers/PredicateRegistrySetup.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";

contract PredicateRegistryOwnershipTest is PredicateRegistrySetup {
    Ownable2StepUpgradeable ownablePredicateRegistry;
    address newOwner;
    address randomAddress;

    function setUp() public override {
        super.setUp();
        ownablePredicateRegistry = Ownable2StepUpgradeable(address(predicateRegistry));
        (newOwner,) = makeAddrAndKey("newOwner");
        (randomAddress,) = makeAddrAndKey("random");
    }

    function testOwnerIsUninitializedFromConstructor() public {
        // owner is not set from constructor
        PredicateRegistry scopedPredicateRegistry = new PredicateRegistry();
        assertEq(Ownable(address(scopedPredicateRegistry)).owner(), address(0));
    }

    function testOwnerIsOwnerByDefault() public {
        // owner is the owner of the contract
        assertTrue(address(owner) == predicateRegistry.owner());
    }

    function testRandomAccountCannotTransferOwnership() public {
        // random address cannot transfer ownership
        vm.expectRevert();
        vm.prank(randomAddress);
        ownablePredicateRegistry.transferOwnership(newOwner);
    }

    function testOwnershipTransfer() public {
        // owner can transfer ownership
        vm.prank(owner);
        ownablePredicateRegistry.transferOwnership(newOwner);
        assertEq(ownablePredicateRegistry.owner(), owner);
        assertEq(ownablePredicateRegistry.pendingOwner(), newOwner);

        // random address cannot accept ownership
        vm.prank(randomAddress);
        vm.expectRevert();
        ownablePredicateRegistry.acceptOwnership();

        // new owner can accept ownership
        vm.prank(newOwner);
        ownablePredicateRegistry.acceptOwnership();
        assertEq(ownablePredicateRegistry.owner(), newOwner);
        assertEq(ownablePredicateRegistry.pendingOwner(), address(0));
    }

    function testOwnershipCancellation() public {
        // owner can transfer ownership
        vm.startPrank(owner);
        ownablePredicateRegistry.transferOwnership(newOwner);
        ownablePredicateRegistry.transferOwnership(address(0));
        vm.stopPrank();

        // new owner cannot accept ownership
        vm.prank(newOwner);
        vm.expectRevert();
        ownablePredicateRegistry.acceptOwnership();
    }

    function testRenounceOwnership() public {
        // owner can transfer ownership
        vm.startPrank(owner);
        ownablePredicateRegistry.transferOwnership(newOwner);
        ownablePredicateRegistry.renounceOwnership();
        vm.stopPrank();

        // new owner cannot accept ownership
        vm.prank(newOwner);
        vm.expectRevert();
        ownablePredicateRegistry.acceptOwnership();

        // owner is the owner of the contract
        assertEq(ownablePredicateRegistry.owner(), owner);
        assertEq(ownablePredicateRegistry.pendingOwner(), address(0));
    }
}
