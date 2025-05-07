// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockClient} from "./helpers/mocks/MockClient.sol";
import "./helpers/utility/ServiceManagerSetup.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";

contract OwnershipClientTest is ServiceManagerSetup {
    function test_OwnerIsOwnerByDefault() public {
        assertTrue(address(owner) == ownableClientInterface.owner());
    }

    function test_RandomAccountCannotTransferOwnership() public {
        vm.expectRevert();
        vm.prank(address(44));
        ownableClientInterface.transferOwnership(address(33));
    }
}

contract OwnershipServiceManagerTest is ServiceManagerSetup {
    Ownable2StepUpgradeable ownableSM;
    address newOwner;
    address randomAddress;

    function setUp() public override {
        super.setUp();
        ownableSM = Ownable2StepUpgradeable(address(serviceManager));
        (newOwner,) = makeAddrAndKey("newOwner");
        (randomAddress,) = makeAddrAndKey("random");
    }

    function test_OwnerIsUninitializedFromConstructor() public {
        ServiceManager scopedServiceManager = new ServiceManager();
        assertEq(Ownable(address(scopedServiceManager)).owner(), address(0));
    }

    function test_OwnerIsChangedDuringSetup() public {
        assertEq(ownableSM.owner(), address(this));
    }

    function test_RandomAccountCannotTransferOwnership() public {
        vm.expectRevert();
        vm.prank(randomAddress);
        ownableSM.transferOwnership(newOwner);
    }

    function test_OwnershipTransfer() public {
        vm.prank(ownableSM.owner());
        ownableSM.transferOwnership(newOwner);
        assertEq(ownableSM.owner(), ownableSM.owner());
        assertEq(ownableSM.pendingOwner(), newOwner);

        vm.prank(randomAddress);
        vm.expectRevert();
        ownableSM.acceptOwnership();
        vm.prank(newOwner);
        ownableSM.acceptOwnership();
        assertEq(ownableSM.owner(), newOwner);
    }
    function test_OwnershipCancellation() public {
        vm.startPrank(ownableSM.owner());
        ownableSM.transferOwnership(newOwner);
        ownableSM.transferOwnership(address(0));
        vm.stopPrank();        
        vm.prank(newOwner);
        vm.expectRevert();
        ownableSM.acceptOwnership();
    }

    function test_RenounceOwnership() public {
        vm.startPrank(ownableSM.owner());
        ownableSM.transferOwnership(newOwner);
        ownableSM.renounceOwnership();
        vm.stopPrank();
        assertEq(ownableSM.owner(), address(0));
        assertEq(ownableSM.pendingOwner(), address(0));
        vm.prank(newOwner);
        vm.expectRevert();
        ownableSM.acceptOwnership();
    }
}
