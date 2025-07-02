// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {Task} from "./IServiceManager.sol";

/**
 * @title Minimal interface for a ServiceManager-type contract that forms the single point for an AVS to push updates to EigenLayer
 * @author Predicate Labs, Inc
 */
interface ISimpleServiceManager {
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
     * @notice Verifies if a task is authorized by the required number of operators
     * @param _task Parameters of the task including sender, target, function signature, arguments, quorum count, and expiry block
     * @param signerAddresses Array of addresses of the operators who signed the task
     * @param signatures Array of signatures from the operators authorizing the task
     * @return isVerified Boolean indicating if the task has been verified by the required number of operators
     * @dev This function checks the signatures against the hash of the task parameters to ensure task authenticity and authorization
     */
    function validateSignatures(
        Task memory _task,
        address[] memory signerAddresses,
        bytes[] memory signatures
    ) external returns (bool isVerified);
}
