// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

/**
 * @notice Struct that bundles together a statement's parameters for validation
 * @dev A statement represents a claim or assertion about a transaction to be executed
 */
struct Statement {
    // the unique identifier for the statement
    string uuid;
    // the address of the sender of the statement
    address msgSender;
    // the address of the target contract for the statement
    address target;
    // the value to send with the statement
    uint256 msgValue;
    // the encoded signature and arguments for the statement
    bytes encodedSigAndArgs;
    // the policy associated with the statement
    string policy;
    // the timestamp by which the statement must be executed
    uint256 expiration;
}

/**
 * @notice Struct that bundles together an attestation's parameters for validation
 */
struct Attestation {
    // the unique identifier for the attestation
    string uuid;
    // the timestamp by which the attestation must be executed
    uint256 expiration;
    // the address of the attester
    address attester;
    // the signature from the attestation
    bytes signature;
}

/**
 * @title IPredicateRegistry interface for a registry of policies, operators, and tasks
 * @author Predicate Labs, Inc
 */
interface IPredicateRegistry {
    /**
     * @notice Sets a policy for the sender, defining execution rules or parameters for tasks
     * @param policy string pointing to the policy details
     * @dev Only callable by client contracts or EOAs to associate a policy with their address
     * @dev Emits a PolicySet event upon successful association
     */
    function setPolicy(
        string memory policy
    ) external;

    /**
     * @notice Gets the policy for a client
     * @param client is the address of the client for which the policy is being retrieved
     * @return policy is the identifier for the client's policy
     */
    function getPolicy(
        address client
    ) external view returns (string memory);

    /**
     * @notice Verifies if a statement is authorized by the attester
     * @param _statement Parameters of the statement including sender, target, function signature, arguments, and expiration
     * @param _attestation Attestation from the attester
     * @return isVerified Boolean indicating if the statement has been verified by the predicate registry
     * @dev This function checks the attestation against the hash of the statement parameters to ensure statement authenticity and authorization
     */
    function validateAttestation(
        Statement memory _statement,
        Attestation memory _attestation
    ) external returns (bool isVerified);
}
