// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockClient} from "./helpers/mocks/MockClient.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract MockClientTest is PredicateRegistrySetup {
    MockClient client;

    function setUp() public override {
        super.setUp();
        client = new MockClient(owner, address(predicateRegistry), policyOne);
    }

    function testRegistryIsSet() public {
        assertTrue(address(predicateRegistry) == client.getRegistry());
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
