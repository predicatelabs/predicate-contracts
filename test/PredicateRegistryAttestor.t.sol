// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {PredicateRegistry} from "../src/PredicateRegistry.sol";
import {Task, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract PredicateRegistryTest is PredicateRegistrySetup {
    // extra attestor
    address attestorThree; 
    uint256 attestorThreePk;


    function setUp() public override {
        super.setUp();
        (attestorThree, attestorThreePk) = makeAddrAndKey("attestorThree");
    }

    //attestor tests
    function testIsAttestorRegistered() public {
        assertTrue(predicateRegistry.isAttestorRegistered(attestorOne));
        assertTrue(predicateRegistry.isAttestorRegistered(attestorTwo));

        assertFalse(predicateRegistry.isAttestorRegistered(attestorThree));
    }

    function testRegisteredAttestors() public {
        address[] memory registeredAttestors = predicateRegistry.registeredAttestors();
        assertEq(registeredAttestors.length, 2);
        assertEq(registeredAttestors[0], attestorOne);
        assertEq(registeredAttestors[1], attestorTwo);
    }

    function testOwnerCanRegisterAttestor() public {
        vm.prank(owner);
        predicateRegistry.registerAttestor(attestorThree);
        assertTrue(predicateRegistry.isAttestorRegistered(attestorThree));
        assertEq(predicateRegistry.registeredAttestors().length, 3);
        assertEq(predicateRegistry.registeredAttestors()[2], attestorThree);
    }

    function testCannotRegisterAttestorThatIsAlreadyRegistered() public {
        vm.expectRevert("Predicate.registerAttestor: attestor already registered");
        vm.prank(owner);
        predicateRegistry.registerAttestor(attestorOne);
    }

    function testOwnerCanDeregisterAttestor() public {
        assertTrue(predicateRegistry.isAttestorRegistered(attestorOne));

        vm.prank(owner);
        predicateRegistry.deregisterAttestor(attestorOne);
        assertFalse(predicateRegistry.isAttestorRegistered(attestorOne));
        assertEq(predicateRegistry.registeredAttestors().length, 1);
        assertEq(predicateRegistry.registeredAttestors()[0], attestorTwo);
    }

    function testCannotDeregisterAttestorThatIsNotRegistered() public {
        vm.expectRevert("Predicate.deregisterAttestor: attestor not registered");
        vm.prank(owner);
        predicateRegistry.deregisterAttestor(attestorThree);
    }

    function testRandomAddrCannotRegisterAttestor() public {
        vm.prank(randomAddress);
        vm.expectRevert();
        predicateRegistry.registerAttestor(attestorOne);
    }

    function testRandomAddrCannotDeregisterAttestor() public {
        vm.prank(randomAddress);
        vm.expectRevert();
        predicateRegistry.deregisterAttestor(attestorOne);
    }
    
    function testCannotUseSpentTask() public {
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: policyID,
            quorumThresholdCount: 1,
            expireByTime: block.timestamp + 100
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        bytes memory signature;

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](1);
        signers[0] = operatorOneAlias;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.prank(address(client));
        bool result = serviceManager.validateSignatures(task, signers, signatures);
        assertTrue(result, "First execution should succeed");

        vm.expectRevert();
        serviceManager.validateSignatures(task, signers, signatures);

        Task memory newTask = Task({
            taskId: "newTaskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByTime: block.timestamp + 100
        });

        vm.expectRevert();
        vm.prank(address(client));
        serviceManager.validateSignatures(newTask, signers, signatures);
    }

    function testCannotReplaySignatures() public permissionedOperators prepOperatorRegistration(true) {
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: policyID,
            quorumThresholdCount: 1,
            expireByTime: block.timestamp + 100
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](1);
        signers[0] = operatorOneAlias;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.prank(address(client));
        bool result = serviceManager.validateSignatures(task, signers, signatures);
        assertTrue(result, "First execution is expected to succeed");

        vm.expectRevert();
        vm.prank(address(client));
        serviceManager.validateSignatures(task, signers, signatures);

        Task memory newTask = Task({
            taskId: "newTaskId",
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByTime: block.timestamp + 100
        });

        vm.expectRevert();
        vm.prank(address(client));
        serviceManager.validateSignatures(newTask, signers, signatures);
    }

    function testRevertOnExpiredTask() public permissionedOperators prepOperatorRegistration(true) {
        uint256 expireByTime = block.timestamp - 1;
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: policyID,
            quorumThresholdCount: 1,
            expireByTime: expireByTime
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](1);
        signers[0] = operatorOneAlias;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.expectRevert("Predicate.validateSignatures: transaction expired");
        vm.prank(address(client));
        serviceManager.validateSignatures(task, signers, signatures);
    }

    function cannotSupplySignaturesToTaskWithDifferentDigest()
        public
        permissionedOperators
        prepOperatorRegistration(true)
    {
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByTime: block.timestamp + 100
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        bytes memory signature;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](1);
        signers[0] = operatorOneAlias;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        Task memory newTask = Task({
            taskId: "newTaskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByTime: block.timestamp + 100
        });

        assertTrue(serviceManager.hashTaskWithExpiry(newTask) != taskDigest);

        vm.expectRevert();
        vm.prank(address(client));
        serviceManager.validateSignatures(newTask, signers, signatures);
    }

    function testDeregisteredOperatorCannotValidateSignatures()
        public
        permissionedOperators
        prepOperatorRegistration(true)
    {
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(client),
            value: 0,
            encodedSigAndArgs: "",
            policyID: policyID,
            quorumThresholdCount: 1,
            expireByTime: block.timestamp + 100
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](1);
        signers[0] = operatorOneAlias;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        // Deregister operator
        serviceManager.deregisterOperatorFromAVS(operatorOne);

        vm.prank(address(client));
        vm.expectRevert("Predicate.validateSignatures: Signer is not a registered operator");
        serviceManager.validateSignatures(task, signers, signatures);
    }

    fallback() external payable {}

    receive() external payable {}
}
