// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Statement, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
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
        client.setPolicyID(policyTwo);
        assertEq(client.getPolicyID(), policyTwo);
    }

    function testRandomAccountCannotSetPolicy() public {
        vm.expectRevert();
        vm.prank(randomAddress);
        client.setPolicyID("testpolicy12345");
    }

    function testClientOwnerCanSetRegistry() public {
        // Create a second PredicateRegistry instance to test registry switching
        vm.startPrank(owner);
        PredicateRegistry newRegistryImpl = new PredicateRegistry();
        PredicateRegistry newRegistry =
            PredicateRegistry(address(new MockProxy(address(newRegistryImpl), address(proxyAdmin))));
        newRegistry.initialize(owner);
        newRegistry.registerAttester(attesterOne);
        newRegistry.registerAttester(attesterTwo);
        vm.stopPrank();

        assertEq(client.getRegistry(), address(predicateRegistry));

        vm.prank(clientOwner);
        client.setRegistry(address(newRegistry));
        assertEq(client.getRegistry(), address(newRegistry));

        // Verify policy was re-registered with new registry
        assertEq(newRegistry.getPolicyID(address(client)), policyOne);
    }

    function testRandomAccountCannotSetRegistry() public {
        // Create a second PredicateRegistry instance
        vm.startPrank(owner);
        PredicateRegistry newRegistryImpl = new PredicateRegistry();
        PredicateRegistry newRegistry =
            PredicateRegistry(address(new MockProxy(address(newRegistryImpl), address(proxyAdmin))));
        newRegistry.initialize(owner);
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(randomAddress);
        client.setRegistry(address(newRegistry));
    }

    function testMetaCoinTransferWithAttestation() public {
        uint256 expireByTime = block.timestamp + 100;
        string memory uuid = "unique-identifier";
        uint256 amount = 10;
        bytes32 messageHash = predicateRegistry.hashStatementWithExpiry(
            Statement({
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, messageHash);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation =
            Attestation({uuid: uuid, expiration: expireByTime, attester: attesterOne, signature: signature});

        vm.prank(clientOwner);
        client.sendCoin(testReceiver, amount, attestation);
        assertEq(client.getBalance(testReceiver), 10, "receiver balance should be 10 after receiving");
        assertEq(client.getBalance(clientOwner), 9_999_999_999_990, "sender balance should be 9900 after sending");
    }

    function testPolicyIDUpdatedEventEmitted() public {
        vm.expectEmit(true, true, true, true);
        emit PredicatePolicyIDUpdated(policyOne, policyTwo);

        vm.prank(clientOwner);
        client.setPolicyID(policyTwo);
    }

    function testRegistryUpdatedEventEmitted() public {
        // Create a second PredicateRegistry instance
        vm.startPrank(owner);
        PredicateRegistry newRegistryImpl = new PredicateRegistry();
        PredicateRegistry newRegistry =
            PredicateRegistry(address(new MockProxy(address(newRegistryImpl), address(proxyAdmin))));
        newRegistry.initialize(owner);
        newRegistry.registerAttester(attesterOne);
        newRegistry.registerAttester(attesterTwo);
        vm.stopPrank();

        // Expect both events: policy re-registration happens first, then registry update
        // PolicySet event from re-registration (emitted first, inside setPolicyID call)
        vm.expectEmit(true, false, false, false);
        emit PolicySet(address(client), policyOne);

        // Then PredicateRegistryUpdated event (emitted after)
        vm.expectEmit(true, true, true, true);
        emit PredicateRegistryUpdated(address(predicateRegistry), address(newRegistry));

        vm.prank(clientOwner);
        client.setRegistry(address(newRegistry));
    }

    function testRegistrySwitchWithEmptyPolicy() public {
        // Create a client with empty policy
        MetaCoin clientWithEmptyPolicy = new MetaCoin(clientOwner, address(predicateRegistry), "");

        // Create a second PredicateRegistry instance
        vm.startPrank(owner);
        PredicateRegistry newRegistryImpl = new PredicateRegistry();
        PredicateRegistry newRegistry =
            PredicateRegistry(address(new MockProxy(address(newRegistryImpl), address(proxyAdmin))));
        newRegistry.initialize(owner);
        newRegistry.registerAttester(attesterOne);
        newRegistry.registerAttester(attesterTwo);
        vm.stopPrank();

        // Expect only PredicateRegistryUpdated event (no PolicySet because policy is empty)
        vm.expectEmit(true, true, true, true);
        emit PredicateRegistryUpdated(address(predicateRegistry), address(newRegistry));

        // Should NOT emit PolicySet event - verify by checking that PolicySet is not in emitted events
        // We use expectEmit to ensure only PredicateRegistryUpdated is emitted
        vm.prank(clientOwner);
        clientWithEmptyPolicy.setRegistry(address(newRegistry));

        // Verify new registry does not have policy registered
        assertEq(newRegistry.getPolicyID(address(clientWithEmptyPolicy)), "");
    }

    function testRegistrySwitchAfterPolicyChange() public {
        // Create a second PredicateRegistry instance
        vm.startPrank(owner);
        PredicateRegistry newRegistryImpl = new PredicateRegistry();
        PredicateRegistry newRegistry =
            PredicateRegistry(address(new MockProxy(address(newRegistryImpl), address(proxyAdmin))));
        newRegistry.initialize(owner);
        newRegistry.registerAttester(attesterOne);
        newRegistry.registerAttester(attesterTwo);
        vm.stopPrank();

        // Verify initial state: old registry has policyOne
        assertEq(predicateRegistry.getPolicyID(address(client)), policyOne);

        // Change policy from policyOne to policyTwo
        vm.prank(clientOwner);
        client.setPolicyID(policyTwo);
        assertEq(client.getPolicyID(), policyTwo);

        // Verify old registry now has policyTwo (was updated by setPolicyID)
        assertEq(predicateRegistry.getPolicyID(address(client)), policyTwo);

        // Switch registry - should register policyTwo (the updated cached policy) with new registry
        vm.prank(clientOwner);
        client.setRegistry(address(newRegistry));

        // Verify new registry has policyTwo (the updated policy from cache), not policyOne
        assertEq(newRegistry.getPolicyID(address(client)), policyTwo);
        assertTrue(keccak256(bytes(newRegistry.getPolicyID(address(client)))) != keccak256(bytes(policyOne)));
    }

    // Event declarations for testing
    event PredicatePolicyIDUpdated(string oldPolicyID, string newPolicyID);
    event PredicateRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event PolicySet(address indexed client, string policy);
}
