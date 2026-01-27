// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PredicateClient} from "../../mixins/PredicateClient.sol";

/**
 * @title PredicateHolding
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice Minimal contract that integrates Predicate attestation validation via PredicateClient.
 * @dev This contract holds Predicate configuration (registry + policy ID) but does not
 *      implement any business logic. It can be used as a simple, ownable Predicate client
 *      for storing policy IDs.
 */
contract PredicateHolding is PredicateClient, Ownable {
    /**
     * @notice Initializes ownership and Predicate client configuration
     * @param _owner Address that will own this contract and control configuration
     * @param _registry Address of the PredicateRegistry contract
     * @param _policyID Initial policy identifier for this contract
     */
    constructor(
        address _owner,
        address _registry,
        string memory _policyID
    ) Ownable(_owner) {
        _initPredicateClient(_registry, _policyID);
    }

    /**
     * @notice Updates the policy ID for this contract
     * @dev Restricted to the contract owner
     * @param _policyID The new policy identifier to set
     */
    function setPolicyID(
        string memory _policyID
    ) external onlyOwner {
        _setPolicyID(_policyID);
    }

    /**
     * @notice Updates the PredicateRegistry address for this contract
     * @dev Restricted to the contract owner
     * @param _registry The new PredicateRegistry contract address
     */
    function setRegistry(
        address _registry
    ) public onlyOwner {
        _setRegistry(_registry);
    }
}
