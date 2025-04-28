// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {IPredicateManager, Task} from "../interfaces/IPredicateManager.sol";
import "../interfaces/IPredicateClient.sol";

abstract contract PredicateClient is IPredicateClient {
    /// @notice Struct to contain stateful values for PredicateClient-type contracts
    /// @custom:storage-location erc7201:predicate.storage.PredicateClient
    struct PredicateClientStorage {
        IPredicateManager serviceManager;
        string policyID;
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

    function _initPredicateClient(address _serviceManagerAddress, string memory _policyID) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.serviceManager = IPredicateManager(_serviceManagerAddress);
        _setPolicy(_policyID);
    }

    function _setPolicy(
        string memory _policyID
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.policyID = _policyID;
        $.serviceManager.setPolicy(_policyID);
    }

    function getPolicy() external view override returns (string memory) {
        return _getPolicy();
    }

    function _getPolicy() internal view returns (string memory) {
        return _getPredicateClientStorage().policyID;
    }

    function _setPredicateManager(
        address _predicateManager
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.serviceManager = IPredicateManager(_predicateManager);
    }

    function getPredicateManager() external view override returns (address) {
        return _getPredicateManager();
    }

    function _getPredicateManager() internal view returns (address) {
        return address(_getPredicateClientStorage().serviceManager);
    }

    modifier onlyPredicateServiceManager() {
        if (msg.sender != address(_getPredicateClientStorage().serviceManager)) {
            revert PredicateClient__Unauthorized();
        }
        _;
    }

    /**
     *
     * @notice Validates the transaction by checking the signatures of the operators.
     */
    function _authorizeTransaction(
        PredicateMessage memory _predicateMessage,
        bytes memory _encodedSigAndArgs,
        address _msgSender,
        uint256 _value
    ) internal returns (bool) {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        Task memory task = Task({
            msgSender: _msgSender,
            target: address(this),
            value: _value,
            encodedSigAndArgs: _encodedSigAndArgs,
            policyID: $.policyID,
            quorumThresholdCount: uint32(_predicateMessage.signerAddresses.length),
            taskId: _predicateMessage.taskId,
            expireByBlockNumber: _predicateMessage.expireByBlockNumber
        });
        return
            $.serviceManager.validateSignatures(task, _predicateMessage.signerAddresses, _predicateMessage.signatures);
    }
}
