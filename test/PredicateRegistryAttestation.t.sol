// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {Task, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract PredicateRegistryAttestationTest is PredicateRegistrySetup {
    // extra attestor
    address attestorThree;
    uint256 attestorThreePk;

    function setUp() public override {
        super.setUp();
        (attestorThree, attestorThreePk) = makeAddrAndKey("attestorThree");
    }

    function testValidateAttestation() public {
        Task memory task = Task({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 taskDigest = predicateRegistry.hashTaskWithExpiry(task);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1",
            attestor: attestorOne,
            signature: signature,
            expiration: block.timestamp + 100
        });

        vm.prank(address(this));
        bool result = predicateRegistry.validateAttestation(task, attestation);
        assertTrue(result, "First execution should succeed");
    }

    function testCannotTamperUUID() public {
        Task memory task = Task({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 taskDigest = predicateRegistry.hashTaskWithExpiry(task);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-new",
            attestor: attestorOne,
            signature: signature,
            expiration: block.timestamp + 100
        });

        vm.expectRevert("Predicate.validateAttestation: task ID does not match attestation ID");
        predicateRegistry.validateAttestation(task, attestation);
    }

    function testCannotTamperExpiration() public {
        Task memory task = Task({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 taskDigest = predicateRegistry.hashTaskWithExpiry(task);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1",
            attestor: attestorOne,
            signature: signature,
            expiration: block.timestamp + 200
        });

        vm.expectRevert("Predicate.validateAttestation: task expiration does not match attestation expiration");
        predicateRegistry.validateAttestation(task, attestation);
    }

    function testCannotUseSpentUUID() public {
        Task memory task = Task({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 taskDigest = predicateRegistry.hashTaskWithExpiry(task);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1",
            attestor: attestorOne,
            signature: signature,
            expiration: block.timestamp + 100
        });

        vm.prank(address(this));
        bool result = predicateRegistry.validateAttestation(task, attestation);
        assertTrue(result, "First execution should succeed");

        // cannot use spent UUID
        vm.expectRevert("Predicate.validateAttestation: task ID already spent");
        predicateRegistry.validateAttestation(task, attestation);
    }

    function testCannotUseExpiredAttestation() public {
        Task memory task = Task({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp
        });

        bytes memory signature;
        bytes32 taskDigest = predicateRegistry.hashTaskWithExpiry(task);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation =
            Attestation({uuid: "uuid-1", attestor: attestorOne, signature: signature, expiration: block.timestamp});

        vm.expectRevert("Predicate.validateAttestation: attestation expired");
        vm.warp(block.timestamp + 100);
        predicateRegistry.validateAttestation(task, attestation);
    }

    function testCannotUseInvalidAttestor() public {
        Task memory task = Task({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 taskDigest = predicateRegistry.hashTaskWithExpiry(task);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1",
            attestor: attestorThree,
            signature: signature,
            expiration: block.timestamp + 100
        });

        vm.expectRevert("Predicate.validateAttestation: Invalid signature");
        predicateRegistry.validateAttestation(task, attestation);
    }

    function testCannotUseInvalidSignature() public {
        Task memory task = Task({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory invalidSignature = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));

        Attestation memory attestation = Attestation({
            uuid: "uuid-1",
            attestor: attestorOne,
            signature: invalidSignature,
            expiration: block.timestamp + 100
        });

        vm.expectRevert();
        predicateRegistry.validateAttestation(task, attestation);
    }

    function testCannotUseDifferentAttestor() public {
        Task memory task = Task({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 taskDigest = predicateRegistry.hashTaskWithExpiry(task);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1",
            attestor: attestorTwo,
            signature: signature,
            expiration: block.timestamp + 100
        });

        vm.expectRevert();
        predicateRegistry.validateAttestation(task, attestation);
    }

    function testCannotUseDeregisteredAttestor() public {
        Task memory task = Task({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 taskDigest = predicateRegistry.hashTaskWithExpiry(task);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestorOnePk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1",
            attestor: attestorOne,
            signature: signature,
            expiration: block.timestamp + 100
        });

        vm.prank(address(this));
        bool result = predicateRegistry.validateAttestation(task, attestation);
        assertTrue(result, "First execution should succeed");

        // deregister attestor
        vm.prank(owner);
        predicateRegistry.deregisterAttestor(attestorOne);

        // create new task
        Task memory task2 = Task({
            uuid: "uuid-2",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature2;
        bytes32 taskDigest2 = predicateRegistry.hashTaskWithExpiry(task2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(attestorOnePk, taskDigest2);
        signature2 = abi.encodePacked(r2, s2, v2);

        Attestation memory attestation2 = Attestation({
            uuid: "uuid-2",
            attestor: attestorOne,
            signature: signature2,
            expiration: block.timestamp + 100
        });

        // cannot use deregistered attestor
        vm.expectRevert("Predicate.validateAttestation: Attestor is not a registered attestor");
        predicateRegistry.validateAttestation(task2, attestation2);
    }
}
