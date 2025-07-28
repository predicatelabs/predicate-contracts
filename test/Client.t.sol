// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockClient} from "./helpers/mocks/MockClient.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract MockClientTest is PredicateRegistrySetup {
    function testServiceManagerIsSet() public {
        assertTrue(address(serviceManager) == client.getPredicateManager());
    }

    function testOwnerCanSetPolicy() public {
        vm.prank(owner);
        client.setPolicy(policyID);
        assertEq(client.getPolicy(), policyID);
    }

    function testRandomAccountCannotSetPolicy() public {
        vm.expectRevert();
        vm.prank(address(44));
        client.setPolicy("testpolicy12345");
    }

    function testRandomAccountCannotCallConfidentialFunction() public {
        vm.expectRevert();
        vm.prank(address(44));
        client.incrementCounter();
    }

    function testServiceManagerCanCallConfidentialFunction() public {
        vm.prank(client.getPredicateManager());
        client.incrementCounter();
    }
}
