// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

/**
 * @notice error type for unauthorized access
 */
error PredicateClient__Unauthorized();

/**
 * @notice Interface for a PredicateClient-type contract to set policy, registry and validate tasks
 */
interface IPredicateClient {

    /**
     * @notice Sets a policy for the calling address, associating it with a policy document stored on IPFS.
     * @param _policyID A string representing the policyID from on chain.
     * @dev This function enables clients to define execution rules or parameters for tasks they submit.
     *      The policy governs how tasks submitted by the caller are executed, ensuring compliance with predefined rules.
     */
    function setPolicy(
        string memory _policyID
    ) external;

    /**
     * @notice Sets the Predicate Registry for the calling address
     * @param _registry address of the registry
     * @dev This function enables clients to set the Predicate Registry for the calling address
     * @dev Authorized only by the owner of the contract
     */
    function setRegistry(
        address _registry
    ) external;

    /**
     * @notice Retrieves the policy for the calling address.
     * @return The policyID associated with the calling address.
     */
    function getPolicy() external view returns (string memory);

    /**
     * @notice Function for getting the Predicate Registry
     * @return address of the registry
     */
    function getRegistry() external view returns (address);
}
