// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Task, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
import {MetaCoin} from "../src/examples/inheritance/MetaCoin.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract MetaCoinTest is PredicateRegistrySetup {
    // meta coin contract
    MetaCoin client;

    // accounts
    address testReceiver;
    address clientOwner;

    function setUp() public override {
        // setup predicate registry
        super.setUp();

        // setup test accounts
        testReceiver = makeAddr("testReceiver");
        clientOwner = makeAddr("clientOwner");
                
        // deploy metacoin contract
        client = new MetaCoin(clientOwner, address(predicateRegistry), policyOne);
    }
    
    function testRegistryIsSet() public {
        assertTrue(address(predicateRegistry) == client.getRegistry());
    }

    function testOwnerCanSetPolicy() public {
        vm.prank(clientOwner);
        client.setPolicy(policyTwo);
        assertEq(client.getPolicy(), policyTwo);
    }

    function testRandomAccountCannotSetPolicy() public {
        vm.expectRevert();
        vm.prank(randomAddress);
        client.setPolicy("testpolicy12345");
    }

    function testClientOwnerCanSetRegistry() public {
        address newRegistry = makeAddr("newRegistry");
        assertEq(client.getRegistry(), address(predicateRegistry));

        vm.prank(clientOwner);
        client.setRegistry(newRegistry);
        assertEq(client.getRegistry(), newRegistry);
    }

    function testRandomAccountCannotSetRegistry() public {
        address newRegistry = makeAddr("newRegistry");
        vm.expectRevert();
        vm.prank(randomAddress);
        client.setRegistry(newRegistry);
    }

    function testMetaCoinTransferWithAttestation() public {
        uint256 expireByTime = block.timestamp + 100;
        string memory uuid = "unique-identifier";
        uint256 amount = 10;
        bytes32 messageHash = predicateRegistry.hashTaskWithExpiry(
            Task({
                uuid: uuid,
                msgSender: clientOwner,
                target: address(client),
                msgValue: 0,
                encodedSigAndArgs: abi.encodeWithSignature("_sendCoin(address,uint256)", testReceiver, amount),
                policy: policyOne,
                expiration: expireByTime
            })
        );

        bytes memory signature;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, messageHash);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: uuid,
            expiration: expireByTime,
            attestor: attestorOne,
            signature: signature
        });

        vm.prank(clientOwner);
        client.sendCoin(testReceiver, amount, attestation);
        assertEq(client.getBalance(testReceiver), 10, "receiver balance should be 10 after receiving");
        assertEq(
            client.getBalance(clientOwner), 9_999_999_999_990, "sender balance should be 9900 after sending"
        );
    }
}
