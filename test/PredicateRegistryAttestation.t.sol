// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {Statement, Attestation} from "../src/interfaces/IPredicateRegistry.sol";
import "./helpers/PredicateRegistrySetup.sol";

contract PredicateRegistryAttestationTest is PredicateRegistrySetup {
    // extra attester
    address attesterThree;
    uint256 attesterThreePk;

    function setUp() public override {
        super.setUp();
        (attesterThree, attesterThreePk) = makeAddrAndKey("attesterThree");
    }

    function testValidateAttestation() public {
        Statement memory statement = Statement({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 statementDigest = predicateRegistry.hashStatementWithExpiry(statement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, statementDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1", attester: attesterOne, signature: signature, expiration: block.timestamp + 100
        });

        vm.prank(address(this));
        bool result = predicateRegistry.validateAttestation(statement, attestation);
        assertTrue(result, "First execution should succeed");
    }

    function testCannotTamperUUID() public {
        Statement memory statement = Statement({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 statementDigest = predicateRegistry.hashStatementWithExpiry(statement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, statementDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-new", attester: attesterOne, signature: signature, expiration: block.timestamp + 100
        });

        vm.expectRevert("Predicate.validateAttestation: statement UUID does not match attestation UUID");
        predicateRegistry.validateAttestation(statement, attestation);
    }

    function testCannotTamperExpiration() public {
        Statement memory statement = Statement({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 statementDigest = predicateRegistry.hashStatementWithExpiry(statement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, statementDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1", attester: attesterOne, signature: signature, expiration: block.timestamp + 200
        });

        vm.expectRevert("Predicate.validateAttestation: statement expiration does not match attestation expiration");
        predicateRegistry.validateAttestation(statement, attestation);
    }

    function testCannotUseSpentUUID() public {
        Statement memory statement = Statement({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 statementDigest = predicateRegistry.hashStatementWithExpiry(statement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, statementDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1", attester: attesterOne, signature: signature, expiration: block.timestamp + 100
        });

        vm.prank(address(this));
        bool result = predicateRegistry.validateAttestation(statement, attestation);
        assertTrue(result, "First execution should succeed");

        // cannot use spent UUID
        vm.expectRevert("Predicate.validateAttestation: statement UUID already used");
        predicateRegistry.validateAttestation(statement, attestation);
    }

    function testCannotUseExpiredAttestation() public {
        Statement memory statement = Statement({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp
        });

        bytes memory signature;
        bytes32 statementDigest = predicateRegistry.hashStatementWithExpiry(statement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, statementDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation =
            Attestation({uuid: "uuid-1", attester: attesterOne, signature: signature, expiration: block.timestamp});

        vm.expectRevert("Predicate.validateAttestation: attestation expired");
        vm.warp(block.timestamp + 100);
        predicateRegistry.validateAttestation(statement, attestation);
    }

    function testCannotUseInvalidAttester() public {
        Statement memory statement = Statement({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 statementDigest = predicateRegistry.hashStatementWithExpiry(statement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, statementDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1", attester: attesterThree, signature: signature, expiration: block.timestamp + 100
        });

        vm.expectRevert("Predicate.validateAttestation: Invalid signature");
        predicateRegistry.validateAttestation(statement, attestation);
    }

    function testCannotUseInvalidSignature() public {
        Statement memory statement = Statement({
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
            uuid: "uuid-1", attester: attesterOne, signature: invalidSignature, expiration: block.timestamp + 100
        });

        vm.expectRevert();
        predicateRegistry.validateAttestation(statement, attestation);
    }

    function testCannotUseDifferentAttester() public {
        Statement memory statement = Statement({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 statementDigest = predicateRegistry.hashStatementWithExpiry(statement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, statementDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1", attester: attesterTwo, signature: signature, expiration: block.timestamp + 100
        });

        vm.expectRevert();
        predicateRegistry.validateAttestation(statement, attestation);
    }

    function testCannotUseDeregisteredAttester() public {
        Statement memory statement = Statement({
            uuid: "uuid-1",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 statementDigest = predicateRegistry.hashStatementWithExpiry(statement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, statementDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-1", attester: attesterOne, signature: signature, expiration: block.timestamp + 100
        });

        vm.prank(address(this));
        bool result = predicateRegistry.validateAttestation(statement, attestation);
        assertTrue(result, "First execution should succeed");

        // deregister attester
        vm.prank(owner);
        predicateRegistry.deregisterAttester(attesterOne);

        // create new statement
        Statement memory statement2 = Statement({
            uuid: "uuid-2",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature2;
        bytes32 statementDigest2 = predicateRegistry.hashStatementWithExpiry(statement2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(attesterOnePk, statementDigest2);
        signature2 = abi.encodePacked(r2, s2, v2);

        Attestation memory attestation2 = Attestation({
            uuid: "uuid-2", attester: attesterOne, signature: signature2, expiration: block.timestamp + 100
        });

        // cannot use deregistered attester
        vm.expectRevert("Predicate.validateAttestation: Attester is not a registered attester");
        predicateRegistry.validateAttestation(statement2, attestation2);
    }

    function testCrossChainReplayPrevention() public {
        Statement memory statement = Statement({
            uuid: "uuid-crosschain",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature;
        bytes32 statementDigest = predicateRegistry.hashStatementWithExpiry(statement);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterOnePk, statementDigest);
        signature = abi.encodePacked(r, s, v);

        Attestation memory attestation = Attestation({
            uuid: "uuid-crosschain", attester: attesterOne, signature: signature, expiration: block.timestamp + 100
        });

        vm.prank(address(this));
        bool result = predicateRegistry.validateAttestation(statement, attestation);
        assertTrue(result, "Should succeed on original chain");

        // Create a new statement with same parameters but different UUID (to avoid UUID reuse)
        // Sign it on original chain but don't validate yet
        Statement memory statement2 = Statement({
            uuid: "uuid-crosschain-2",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        bytes memory signature2;
        bytes32 statementDigest2 = predicateRegistry.hashStatementWithExpiry(statement2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(attesterOnePk, statementDigest2);
        signature2 = abi.encodePacked(r2, s2, v2);

        // Now change to a different chain and try to use the signature from original chain
        // The signature was created for the original chain's hash (includes original chain ID)
        // but validation will compute hash with new chain ID, causing signature mismatch
        vm.chainId(999);
        Attestation memory attestation2 = Attestation({
            uuid: "uuid-crosschain-2", attester: attesterOne, signature: signature2, expiration: block.timestamp + 100
        });

        vm.prank(address(this));
        vm.expectRevert("Predicate.validateAttestation: Invalid signature");
        predicateRegistry.validateAttestation(statement2, attestation2);
    }

    function testHashStatementWithExpiryIncludesChainId() public {
        Statement memory statement = Statement({
            uuid: "uuid-hashtest",
            msgSender: address(this),
            target: address(this),
            msgValue: 0,
            encodedSigAndArgs: "",
            policy: policyOne,
            expiration: block.timestamp + 100
        });

        vm.chainId(1);
        bytes32 hashChain1 = predicateRegistry.hashStatementWithExpiry(statement);

        vm.chainId(1);
        bytes32 hashChain1Again = predicateRegistry.hashStatementWithExpiry(statement);
        assertEq(hashChain1Again, hashChain1, "Same chain ID should produce same hash");

        vm.chainId(137);
        bytes32 hashChain137 = predicateRegistry.hashStatementWithExpiry(statement);
        assertNotEq(hashChain137, hashChain1, "Different chain ID should produce different hash");

        vm.chainId(42_161);
        bytes32 hashChain42161 = predicateRegistry.hashStatementWithExpiry(statement);
        assertNotEq(hashChain42161, hashChain1, "Different chain ID should produce different hash");
        assertNotEq(hashChain42161, hashChain137, "Different chain IDs should produce different hashes");

        vm.chainId(1);
        bytes32 hashChain1Restored = predicateRegistry.hashStatementWithExpiry(statement);
        assertEq(hashChain1Restored, hashChain1, "Returning to same chain ID should produce same hash");
    }
}
