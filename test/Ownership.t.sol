// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockClient} from "./helpers/mocks/MockClient.sol";
import "./helpers/utility/ServiceManagerSetup.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";

contract OwnershipClientTest is ServiceManagerSetup {
    function test_OwnerIsOwnerByDefault() public {
        console.log(address(owner));
        console.log(address(ownableClientInterface));
        console.log(address(this));
        assertTrue(address(owner) == ownableClientInterface.owner());
    }

    function test_RandomAccountCannotTransferOwnership() public {
        vm.expectRevert();
        vm.prank(address(44));
        ownableClientInterface.transferOwnership(address(33));
    }
}

contract OwnershipServiceManagerTest is ServiceManagerSetup {
    function test_OwnerIsUninitializedFromConstructor() public {
        ServiceManager scopedServiceManager = new ServiceManager();
        Ownable ownableSM = Ownable(address(scopedServiceManager));
        assertTrue(address(0) == ownableSM.owner());
    }

    function test_OwnerIsChangedDuringSetup() public {
        Ownable ownableSM = Ownable(address(serviceManager));
        assertTrue(address(this) == ownableSM.owner());
    }

    function test_RandomAccountCannotTransferOwnership() public {
        Ownable ownableSM = Ownable(address(serviceManager));
        vm.expectRevert();
        vm.prank(address(44));
        ownableSM.transferOwnership(address(33));
    }

    function test_OwnerCanTransferOwnership() public {
        (address newOwner, ) = makeAddrAndKey("newOwner");
        Ownable2StepUpgradeable ownableSM = Ownable2StepUpgradeable(address(serviceManager));
        vm.prank(ownableSM.owner());
        ownableSM.transferOwnership(newOwner);
        vm.prank(newOwner);
        ownableSM.acceptOwnership();
        assertTrue(newOwner == ownableSM.owner());
    }
}
