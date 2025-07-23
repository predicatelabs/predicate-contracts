// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {Task, Attestation} from "./IPredicateRegistry.sol";

/**
 * @title Interface for a PredicateSpokeRegistry contracts deployed on different EVM chains, except Ethereum mainnet
 * @author Predicate Labs, Inc
 */
interface IPredicateSpokeRegistry {

    /**
     * @notice Verifies if a task is authorized by the required number of attestors
     * @param _task Parameters of the task including sender, target, function signature, arguments, quorum count, and expiry block
     * @param _attestation Attestation from the attestor authorizing the task
     * @return isVerified Boolean indicating if the task has been verified by the required number of attestors
     * @dev This function checks the attestation against the hash of the task parameters to ensure task authenticity and authorization
     */
    function validateAttestation(
        Task memory _task,
        Attestation memory _attestation
    ) external returns (bool isVerified);
}
