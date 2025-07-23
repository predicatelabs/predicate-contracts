// SPDX-License-Identifier: MIT

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
    // the policy ID associated with the task
    string policyID;
    // the timestamp by which the task must be executed
    uint256 expiration;
}

/**
 * @notice Struct that bundles together an attestation's parameters for validation
 */
struct Attestation {
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
     * @notice Sets a policy ID for the sender, defining execution rules or parameters for tasks
     * @param policyID string pointing to the policy details
     * @dev Only callable by client contracts or EOAs to associate a policy with their address
     * @dev Emits a SetPolicy event upon successful association
     */
    function setPolicy(
        string memory policyID
    ) external;

    /**
     * @notice Deploys a policy with ID with execution rules or parameters for tasks
     * @param _policyID string pointing to the policy details
     * @param _policy string containing the policy details
     * @param _quorumThreshold The number of signatures required to authorize a task
     * @dev Only callable by service manager deployer
     * @dev Emits a DeployedPolicy event upon successful deployment
     */
    function deployPolicy(string memory _policyID, string memory _policy, uint256 _quorumThreshold) external;

    /**
     * @notice Gets array of deployed policies
     */
    function getDeployedPolicies() external view returns (string[] memory);

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
