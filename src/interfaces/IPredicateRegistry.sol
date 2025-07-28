// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

/**
 * @notice Struct that bundles together a task's parameters for validation
 */
struct Task {
    // the unique identifier for the task
    string uuid;
    // the address of the sender of the task
    address msgSender;
    // the address of the target contract for the task
    address target;
    // the value to send with the task
    uint256 msgValue;
    // the encoded signature and arguments for the task
    bytes encodedSigAndArgs;
    // the policy associated with the task
    string policy;
    // the timestamp by which the task must be executed
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
    // the address of the attestor
    address attestor;
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
     * @notice Disables a policy for which clients can use
     * @param policy is the identifier for the policy
     * @dev Emits a PolicyDisabled event upon successful disassociation
     */
    function disablePolicy(string memory policy) external;

    /**
     * @notice Enables a policy for which clients can use
     * @param policy is the identifier for the policy
     * @dev Emits a PolicyEnabled event upon successful association
     */
    function enablePolicy(string memory policy) external;

    /**
     * @notice Overrides the policy for a client
     * @param policy is the identifier for the policy
     * @param client is the address of the client for which the policy is being overridden
     * @dev Emits a PolicySet event upon successful association
     */
    function overrideClientPolicy(string memory policy, address client) external;

    /**
     * @notice Gets array of enabled policies
     * @return array of enabled policies
     */
    function getEnabledPolicies() external view returns (string[] memory);

    /**
     * @notice Gets the policy for a client
     * @param client is the address of the client for which the policy is being retrieved
     * @return policy is the identifier for the client's policy
     */
    function getPolicy(address client) external view returns (string memory);

    /**
     * @notice Verifies if a task is authorized by the attestor
     * @param _task Parameters of the task including sender, target, function signature, arguments, quorum count, and expiry block
     * @param _attestation Attestation from the attestor
     * @return isVerified Boolean indicating if the task has been verified by the predicate registry
     * @dev This function checks the attestation against the hash of the task parameters to ensure task authenticity and authorization
     */
    function validateAttestation(
        Task memory _task,
        Attestation memory _attestation
    ) external returns (bool isVerified);
}
