// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {ServiceManagerSetup} from "./helpers/utility/ServiceManagerSetup.sol";

contract ServiceManagerAllowRegistrationsTest is ServiceManagerSetup {
    function testOwnerCanToggleAllowRegistrations() public {
        // set to false
        vm.prank(address(this));
        serviceManager.setAllowRegistrations(false);
        assertEq(serviceManager.allowRegistrations(), false);

        // set back to true
        vm.prank(address(this));
        serviceManager.setAllowRegistrations(true);
        assertEq(serviceManager.allowRegistrations(), true);
    }

    function testNonOwnerCannotSetAllowRegistrations() public {
        address nonOwner = address(0xBEEF);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        serviceManager.setAllowRegistrations(false);
    }
}


