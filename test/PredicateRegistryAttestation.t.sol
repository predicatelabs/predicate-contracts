// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

// import {Test} from "forge-std/Test.sol";
// import {Task, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
// import "./helpers/PredicateRegistrySetup.sol";

// contract PredicateRegistryAttestationTest is PredicateRegistrySetup {
//     // extra attestor
//     address attestorThree; 
//     uint256 attestorThreePk;

//     function setUp() public override {
//         super.setUp();
//         (attestorThree, attestorThreePk) = makeAddrAndKey("attestorThree");
//     }
    
//     function testCannotUseSpentTask() public {
//         Task memory task = Task({
//             uuid: "uuid-1",
//             msgSender: address(this),
//             target: address(this),
//             msgValue: 0,
//             encodedSigAndArgs: "",
//             policy: policyOne,
//             expiration: block.timestamp + 100
//         });

//         // sign task
//         bytes memory signature;
//         bytes32 taskDigest = predicateRegistry.hashTaskWithExpiry(task);
//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, taskDigest);
//         signature = abi.encodePacked(r, s, v);

//         // create attestation
//         Attestation memory attestation = Attestation({
//             uuid: "uuid-1",
//             attestor: attestorOne,
//             signature: signature,
//             expiration: block.timestamp + 100
//         });

//         // validate attestation
//         vm.prank(address(this));
//         bool result = predicateRegistry.validateAttestation(task,attestation);
//         assertTrue(result, "First execution should succeed");

//         vm.expectRevert();
//         serviceManager.validateSignatures(task, signers, signatures);

//         Task memory newTask = Task({
//             taskId: "newTaskId",
//             msgSender: address(this),
//             target: address(this),
//             value: 0,
//             encodedSigAndArgs: "",
//             policyID: "testPolicy",
//             quorumThresholdCount: 1,
//             expireByTime: block.timestamp + 100
//         });

//         vm.expectRevert();
//         vm.prank(address(client));
//         serviceManager.validateSignatures(newTask, signers, signatures);
//     }

//     function testCannotReplaySignatures() public permissionedOperators prepOperatorRegistration(true) {
//         Task memory task = Task({
//             taskId: "taskId",
//             msgSender: address(this),
//             target: address(client),
//             value: 0,
//             encodedSigAndArgs: "",
//             policyID: policyID,
//             quorumThresholdCount: 1,
//             expireByTime: block.timestamp + 100
//         });

//         bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
//         bytes memory signature = abi.encodePacked(r, s, v);

//         address[] memory signers = new address[](1);
//         signers[0] = operatorOneAlias;

//         bytes[] memory signatures = new bytes[](1);
//         signatures[0] = signature;

//         vm.prank(address(client));
//         bool result = serviceManager.validateSignatures(task, signers, signatures);
//         assertTrue(result, "First execution is expected to succeed");

//         vm.expectRevert();
//         vm.prank(address(client));
//         serviceManager.validateSignatures(task, signers, signatures);

//         Task memory newTask = Task({
//             taskId: "newTaskId",
//             msgSender: address(this),
//             target: address(client),
//             value: 0,
//             encodedSigAndArgs: "",
//             policyID: "testPolicy",
//             quorumThresholdCount: 1,
//             expireByTime: block.timestamp + 100
//         });

//         vm.expectRevert();
//         vm.prank(address(client));
//         serviceManager.validateSignatures(newTask, signers, signatures);
//     }

//     function testRevertOnExpiredTask() public permissionedOperators prepOperatorRegistration(true) {
//         uint256 expireByTime = block.timestamp - 1;
//         Task memory task = Task({
//             taskId: "taskId",
//             msgSender: address(this),
//             target: address(client),
//             value: 0,
//             encodedSigAndArgs: "",
//             policyID: policyID,
//             quorumThresholdCount: 1,
//             expireByTime: expireByTime
//         });

//         bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
//         bytes memory signature = abi.encodePacked(r, s, v);

//         address[] memory signers = new address[](1);
//         signers[0] = operatorOneAlias;

//         bytes[] memory signatures = new bytes[](1);
//         signatures[0] = signature;

//         vm.expectRevert("Predicate.validateSignatures: transaction expired");
//         vm.prank(address(client));
//         serviceManager.validateSignatures(task, signers, signatures);
//     }

//     function cannotSupplySignaturesToTaskWithDifferentDigest()
//         public
//         permissionedOperators
//         prepOperatorRegistration(true)
//     {
//         Task memory task = Task({
//             taskId: "taskId",
//             msgSender: address(this),
//             target: address(client),
//             value: 0,
//             encodedSigAndArgs: "",
//             policyID: "testPolicy",
//             quorumThresholdCount: 1,
//             expireByTime: block.timestamp + 100
//         });

//         bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

//         bytes memory signature;
//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
//         signature = abi.encodePacked(r, s, v);

//         address[] memory signers = new address[](1);
//         signers[0] = operatorOneAlias;

//         bytes[] memory signatures = new bytes[](1);
//         signatures[0] = signature;

//         Task memory newTask = Task({
//             taskId: "newTaskId",
//             msgSender: address(this),
//             target: address(this),
//             value: 0,
//             encodedSigAndArgs: "",
//             policyID: "testPolicy",
//             quorumThresholdCount: 1,
//             expireByTime: block.timestamp + 100
//         });

//         assertTrue(serviceManager.hashTaskWithExpiry(newTask) != taskDigest);

//         vm.expectRevert();
//         vm.prank(address(client));
//         serviceManager.validateSignatures(newTask, signers, signatures);
//     }

//     function testDeregisteredOperatorCannotValidateSignatures()
//         public
//         permissionedOperators
//         prepOperatorRegistration(true)
//     {
//         Task memory task = Task({
//             taskId: "taskId",
//             msgSender: address(this),
//             target: address(client),
//             value: 0,
//             encodedSigAndArgs: "",
//             policyID: policyID,
//             quorumThresholdCount: 1,
//             expireByTime: block.timestamp + 100
//         });

//         bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
//         bytes memory signature = abi.encodePacked(r, s, v);

//         address[] memory signers = new address[](1);
//         signers[0] = operatorOneAlias;

//         bytes[] memory signatures = new bytes[](1);
//         signatures[0] = signature;

//         // Deregister operator
//         serviceManager.deregisterOperatorFromAVS(operatorOne);

//         vm.prank(address(client));
//         vm.expectRevert("Predicate.validateSignatures: Signer is not a registered operator");
//         serviceManager.validateSignatures(task, signers, signatures);
//     }

//     fallback() external payable {}

//     receive() external payable {}
// }
