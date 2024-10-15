// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {IServiceManager, Task} from "../interfaces/IServiceManager.sol";
import {IPredicateClient, PredicateMessage} from "../interfaces/IPredicateClient.sol";

contract PredicateClient is IPredicateClient, Ownable {
    error PredicateClient__Unauthorized();

    IServiceManager public serviceManager;
    string public policyID;

    /**
     * @notice Restricts access to the Predicate ServiceManager
     */
    modifier onlyPredicateServiceManager() {
        if (msg.sender != address(serviceManager)) {
            revert PredicateClient__Unauthorized();
        }
        _;
    }

    /**
     * @notice Updates the policy ID
     * @param _policyID policy ID from onchain
     */
    function setPolicy(
        string memory _policyID
    ) external onlyOwner {
        policyID = _policyID;
        serviceManager.setPolicy(_policyID);
    }

    /**
     * @notice Internal function for setting the ServiceManager
     * @param _serviceManager address of the service manager
     */
    function setServiceManager(
        address _serviceManager
    ) public onlyOwner {
        serviceManager = IServiceManager(_serviceManager);
    }

    function _authorizeTransaction(
        PredicateMessage memory _predicateMessage,
        bytes memory _encodedSigAndArgs
    ) internal returns (bool) {
        Task memory task = Task({
            msgSender: msg.sender,
            target: address(this),
            value: msg.value,
            encodedSigAndArgs: _encodedSigAndArgs,
            policyID: policyID,
            quorumThresholdCount: uint32(_predicateMessage.signerAddresses.length),
            taskId: _predicateMessage.taskId,
            expireByBlockNumber: _predicateMessage.expireByBlockNumber
        });

        return serviceManager.validateSignatures(task, _predicateMessage.signerAddresses, _predicateMessage.signatures);
    }
}
