// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IPredicateRegistry, Attestation, Task} from "../interfaces/IPredicateRegistry.sol";
import "../interfaces/IPredicateClient.sol";

abstract contract PredicateClient is IPredicateClient {
    /// @notice Struct to contain stateful values for PredicateClient-type contracts
    /// @custom:storage-location erc7201:predicate.storage.PredicateClient
    struct PredicateClientStorage {
        IPredicateRegistry registry;
        string policy;
    }

    /// @notice the storage slot for the PredicateClientStorage struct
    /// @dev keccak256(abi.encode(uint256(keccak256("predicate.storage.PredicateClient")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PREDICATE_CLIENT_STORAGE_SLOT =
        0x804776a84f3d03ad8442127b1451e2fbbb6a715c681d6a83c9e9fca787b99300;

    function _getPredicateClientStorage() private pure returns (PredicateClientStorage storage $) {
        assembly {
            $.slot := _PREDICATE_CLIENT_STORAGE_SLOT
        }
    }

    function _initPredicateClient(address _registryAddress, string memory _policy) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.registry = IPredicateRegistry(_registryAddress);
        _setPolicy(_policy);
    }

    function _setPolicy(
        string memory _policy
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.policy = _policy;
        $.registry.setPolicy(_policy);
    }

    function getPolicy() external view returns (string memory) {
        return _getPolicy();
    }

    function _getPolicy() internal view returns (string memory) {
        return _getPredicateClientStorage().policy;
    }

    function _setRegistry(
        address _registryAddress
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.registry = IPredicateRegistry(_registryAddress);
    }

    function getRegistry() external view returns (address) {
        return _getRegistry();
    }

    function _getRegistry() internal view returns (address) {
        return address(_getPredicateClientStorage().registry);
    }

    modifier onlyPredicateRegistry() {
        if (msg.sender != address(_getPredicateClientStorage().registry)) {
            revert PredicateClient__Unauthorized();
        }
        _;
    }

    /**
     * @notice Validates the transaction by checking the attestation.
     * @param _attestation Attestation from the attester authorizing the task
     * @param _encodedSigAndArgs Encoded signature and arguments for the task
     * @param _msgSender Address of the sender of the task
     * @param _msgValue Value to send with the task
     * @return bool indicating if the task has been validated
     */
    function _authorizeTransaction(
        Attestation memory _attestation,
        bytes memory _encodedSigAndArgs,
        address _msgSender,
        uint256 _msgValue
    ) internal returns (bool) {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        Task memory task = Task({
            msgSender: _msgSender,
            target: address(this),
            msgValue: _msgValue,
            encodedSigAndArgs: _encodedSigAndArgs,
            policy: $.policy,
            expiration: _attestation.expiration,
            uuid: _attestation.uuid
        });
        return $.registry.validateAttestation(task, _attestation);
    }
}
