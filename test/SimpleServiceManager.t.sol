// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {ServiceManager} from "../src/ServiceManager.sol";
import {Task} from "../src/interfaces/IPredicateManager.sol";
import {MockClient} from "./helpers/mocks/MockClient.sol";
import {MockProxy} from "./helpers/mocks/MockProxy.sol";
import {MockProxyAdmin} from "./helpers/mocks/MockProxyAdmin.sol";
import {MockStakeRegistry} from "./helpers/mocks/MockStakeRegistry.sol";
import {MockDelegationManager} from "./helpers/mocks/MockDelegationManager.sol";
import {IPauserRegistry} from "./helpers/eigenlayer/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "./helpers/eigenlayer/interfaces/IDelegationManager.sol";
import {MockStrategyManager} from "./helpers/mocks/MockStrategyManager.sol";
import {MockEigenPodManager} from "./helpers/mocks/MockEigenPodManager.sol";
import {SimpleServiceManagerSetup} from "./helpers/utility/SimpleServiceManagerSetup.sol";

import "./helpers/utility/TestUtils.sol";
import "./helpers/utility/ServiceManagerSetup.sol";
import "./helpers/utility/OperatorTestPrep.sol";

contract SimpleServiceManager is SimpleServiceManagerSetup {
    string constant TASK_ID = "test-task-001";
    uint32 constant QUORUM_THRESHOLD = 1;

    function testValidateSignaturesSuccessful() public {
        Task memory task = Task({
            taskId: TASK_ID,
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: policyID,
            quorumThresholdCount: QUORUM_THRESHOLD,
            expireByTime: block.timestamp + 100
        });

        bytes32 taskHash = new ServiceManager().hashTaskWithExpiry(task);

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(operatorOneAliasPk, taskHash);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        address[] memory signerAddresses = new address[](1);
        bytes[] memory signatures = new bytes[](1);
        signerAddresses[0] = operatorOneAlias;
        signatures[0] = signature1;

        vm.prank(address(client));
        bool isVerified = simpleServiceManager.validateSignatures(task, signerAddresses, signatures);
        assertTrue(isVerified, "Signature validation should pass");
    }

    function testRevertOnExpiredTask() public {
        uint256 expireByTime = block.timestamp - 1;

        Task memory task = Task({
            taskId: TASK_ID,
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: policyID,
            quorumThresholdCount: QUORUM_THRESHOLD,
            expireByTime: expireByTime
        });

        bytes32 taskHash = new ServiceManager().hashTaskWithExpiry(task);

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(operatorOneAliasPk, taskHash);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        address[] memory signerAddresses = new address[](1);
        bytes[] memory signatures = new bytes[](1);
        signerAddresses[0] = operatorOneAlias;
        signatures[0] = signature1;

        vm.expectRevert("Predicate.validateSignatures: transaction expired");
        vm.prank(address(client));
        simpleServiceManager.validateSignatures(task, signerAddresses, signatures);
    }

    function testSyncPolicies() public {
        string[] memory policyIDs = new string[](2);
        uint32[] memory thresholds = new uint32[](2);

        policyIDs[0] = "policy-001";
        policyIDs[1] = "policy-002";
        thresholds[0] = 2;
        thresholds[1] = 3;

        vm.prank(owner);
        simpleServiceManager.syncPolicies(policyIDs, thresholds);

        // Verify thresholds were set correctly
        assertEq(simpleServiceManager.policyIDToThreshold(policyIDs[0]), 2);
        assertEq(simpleServiceManager.policyIDToThreshold(policyIDs[1]), 3);

        // Verify policy IDs were added to deployedPolicyIDs array
        // note: a policy was already deployed in the simple service manager setup
        assertEq(simpleServiceManager.deployedPolicyIDs(1), policyIDs[0]);
        assertEq(simpleServiceManager.deployedPolicyIDs(2), policyIDs[1]);
    }

    function testValidateSignaturesAfterSigningKeyUpdate() public {
        Task memory newTask = Task({
            taskId: TASK_ID,
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: policyID,
            quorumThresholdCount: QUORUM_THRESHOLD,
            expireByTime: block.timestamp + 100
        });

        bytes32 taskHash = new ServiceManager().hashTaskWithExpiry(newTask);

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(operatorOneAliasPk, taskHash);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        address[] memory signerAddresses = new address[](1);
        bytes[] memory signatures = new bytes[](1);
        signerAddresses[0] = operatorOneAlias;
        signatures[0] = signature1;

        vm.prank(address(client));
        bool isVerified = simpleServiceManager.validateSignatures(newTask, signerAddresses, signatures);
        assertTrue(isVerified, "Signature validation should pass");

        (address newSigningKey, uint256 newSigningKeyPk) = makeAddrAndKey("newOperatorOneSigningKey");

        address[] memory registrationKeys = new address[](1);
        registrationKeys[0] = operatorOne;

        address[] memory signingKeys = new address[](1);
        signingKeys[0] = newSigningKey;

        vm.prank(owner);
        simpleServiceManager.syncOperators(registrationKeys, signingKeys, new address[](0));
        assertTrue(
            simpleServiceManager.signingKeyToOperatorAddress(newSigningKey) == operatorOne,
            "New signing key should map to operator one"
        );

        newTask = Task({
            taskId: "new-task",
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: policyID,
            quorumThresholdCount: QUORUM_THRESHOLD,
            expireByTime: block.timestamp + 100
        });

        taskHash = new ServiceManager().hashTaskWithExpiry(newTask);

        (v1, r1, s1) = vm.sign(newSigningKeyPk, taskHash);
        bytes memory newSignature = abi.encodePacked(r1, s1, v1);

        signerAddresses[0] = newSigningKey;
        signatures[0] = newSignature;

        vm.prank(address(client));
        isVerified = simpleServiceManager.validateSignatures(newTask, signerAddresses, signatures);
        assertTrue(isVerified, "Signature validation should pass");
    }

    function testSyncOperators() public {
        address[] memory registrationKeys = new address[](2);
        address[] memory signingKeys = new address[](2);
        registrationKeys[0] = operatorOne;
        registrationKeys[1] = operatorTwo;
        signingKeys[0] = operatorOneAlias;
        signingKeys[1] = operatorTwoAlias;

        vm.prank(owner);
        simpleServiceManager.syncOperators(registrationKeys, signingKeys, new address[](0));

        // Verify signing key to operator mappings
        assertEq(simpleServiceManager.signingKeyToOperatorAddress(signingKeys[0]), registrationKeys[0]);
        assertEq(simpleServiceManager.signingKeyToOperatorAddress(signingKeys[1]), registrationKeys[1]);

        //////////////// Test removing an operator and adding a new one ////////////////
        (address operatorThree, uint256 operatorThreePk) = makeAddrAndKey("operatorThree");
        (address operatorThreeAlias, uint256 operatorThreeAliasPk) = makeAddrAndKey("operatorThreeAlias");

        address[] memory newRegistrationKeys = new address[](2);
        address[] memory newSigningKeys = new address[](2);

        newRegistrationKeys[0] = operatorOne;
        newRegistrationKeys[1] = operatorThree;

        newSigningKeys[0] = operatorOneAlias;
        newSigningKeys[1] = operatorThreeAlias;

        // Expect removed operators events
        vm.expectEmit(true, true, true, true);
        emit OperatorRemoved(operatorOne);
        vm.expectEmit(true, true, true, true);
        emit OperatorRemoved(operatorTwo);

        // Expect registered operators events
        vm.expectEmit(true, true, true, true);
        emit OperatorRegistered(operatorOne);
        vm.expectEmit(true, true, true, true);
        emit OperatorRegistered(operatorThree);

        // Sync operators again
        vm.prank(owner);
        simpleServiceManager.syncOperators(newRegistrationKeys, newSigningKeys, registrationKeys);

        // Verify correct signing key mappings
        assertEq(simpleServiceManager.signingKeyToOperatorAddress(newSigningKeys[0]), newRegistrationKeys[0]);
        assertEq(simpleServiceManager.signingKeyToOperatorAddress(newSigningKeys[1]), newRegistrationKeys[1]);

        // operatorTwo should know longer be registered
        assertEq(simpleServiceManager.signingKeyToOperatorAddress(signingKeys[1]), address(0));
    }
}
