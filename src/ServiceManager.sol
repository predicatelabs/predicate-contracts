// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IPredicateRegistry, Task, Attestation} from "./interfaces/IPredicateRegistry.sol";

contract PredicateRegistry is IPredicateRegistry, Initializable, Ownable2StepUpgradeable {
    error PredicateRegistryUnauthorized();

    string[] public enabledPolicyIDs;
    mapping(address => bool) public registeredOperators;
    mapping(string => bool) public enabledPolicyIDs;
    mapping(address => string) public clientToPolicyID;
    mapping(string => bool) public spentTaskIDs;


    event PolicySet(address indexed client, string policyID);
    event PolicyEnabled(string policyID);
    event PolicyDisabled(string policyID);
    event OperatorRegistered(address indexed operator);
    event OperatorDeregistered(address indexed operator);

    event TaskValidated(
        address indexed msgSender,
        address indexed target,
        address indexed attestor,
        uint256 msgValue,
        string policyID,
        string uuid,
        uint256 expiration
    );

    function initialize(
        address _owner
    ) external initializer {
        __Ownable2Step_init();
        __Ownable_init(_owner);
    }


    /**
     * @notice Registers a new operator
     * @param _operator the address of the operator to be registered
     */
    function registerOperator(
        address _operator
    ) external onlyOwner {
        require(!registeredOperators[_operator], "Predicate.registerOperator: operator already registered");
        registeredOperators[_operator] = true;
        emit OperatorRegistered(_operator);
    }


    /**
     * @notice Deregisters an operator
     * @param _operator the address of the operator to be deregistered
     */
    function deregisterOperator(
        address _operator
    ) external onlyOwner {
        require(registeredOperators[_operator], "Predicate.deregisterOperator: operator not registered");
        registeredOperators[_operator] = false;
        emit OperatorDeregistered(_operator);
    }

    /**
     * @notice Deploys a policy for which clients can use
     * @param _policyID is a unique identifier
     * @param _policy is set of formatted rules
     */
    function deployPolicy(
        string memory _policyID,
        string memory _policy,
    ) external onlyOwner {
        require(bytes(idToPolicy[_policyID]).length == 0, "Predicate.deployPolicy: policy exists");
        require(bytes(_policy).length > 0, "Predicate.deployPolicy: policy string cannot be empty");
        idToPolicy[_policyID] = _policy;
        deployedPolicyIDs.push(_policyID);
        emit PolicyDeployed(_policyID, _policy);
    }

    /**
     * @notice Gets array of deployed policies
     * @return array of deployed policies
     */
    function getDeployedPolicies() external view returns (string[] memory) {
        return deployedPolicyIDs;
    }

    /**
     * @notice Sets a policy for the calling contract (msg.sender)
     * @dev Associates a client contract with a specific policy ID. The policy must be previously registered.
     * @param _policyID Identifier of a registered policy to associate with the caller
     */
    function setPolicy(
        string memory _policyID
    ) external {
        require(bytes(_policyID).length > 0, "Predicate.setPolicy: policy ID cannot be empty");
        require(enabledPolicyIDs[_policyID], "Predicate.setPolicy: policy ID not enabled or doesn't exist");
        clientToPolicyID[msg.sender] = _policyID;
        emit PolicySet(msg.sender, _policyID);
    }

    /**
     * @notice Overrides the policy for a specific client address
     * @param _policyID is the unique identifier for the policy
     * @param _clientAddress is the address of the client for which the policy is being overridden
     */
    function overrideClientPolicyID(string memory _policyID, address _clientAddress) external onlyOwner {
        require(bytes(_policyID).length > 0, "Predicate.setPolicy: policy ID cannot be empty");
        require(policyIdToThreshold[_policyID] > 0, "Predicate.setPolicy: policy ID not registered");
        clientToPolicyID[_clientAddress] = _policyID;
        emit PolicySet(_clientAddress, _policyID);
    }

    /**
     * @notice Performs the hashing of an STM task
     * @param _task parameters of the task
     * @return the keccak256 digest of the task
     */
    function hashTaskWithExpiry(
        Task calldata _task
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _task.taskId,
                _task.msgSender,
                _task.target,
                _task.msgValue,
                _task.encodedSigAndArgs,
                _task.policyID,
                _task.expiration
            )
        );
    }

    /**
     * @notice Computes a secure task hash with validation-time context
     * @param _task The task parameters to hash
     * @return bytes32 The keccak256 digest including validation context
     */
    function hashTaskSafe(
        Task calldata _task
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                _task.taskId,
                _task.msgSender,
                msg.sender,
                _task.msgValue,
                _task.encodedSigAndArgs,
                _task.policyID,
                _task.expiration
            )
        );
    }

    /**
     * @notice Validates signatures using the OpenZeppelin ECDSA library for the Predicate Single Transaction Model
     * @param _task the params of the task
     * @param _attestation the attestation from the attestor
     */
    function validateAttestation(
        Task calldata _task,
        Attestation calldata _attestation
    ) external returns (bool isVerified) {
        require(block.timestamp <= _task.expiration, "Predicate.validateAttestation: transaction expired");
        require(!spentTaskIDs[_task.uuid], "Predicate.validateAttestation: task ID already spent");

        bytes32 messageHash = hashTaskSafe(_task);
        address recoveredAttestor = ECDSA.recover(messageHash, _attestation.signature);
        require(recoveredAttestor == _attestation.attestor, "Predicate.validateAttestation: Invalid signature");
        require(registeredOperators[recoveredAttestor], "Predicate.validateAttestation: Attestor is not a registered operator");

        spentTaskIDs[_task.uuid] = true;

        emit TaskValidated(
            _task.msgSender,
            _task.target,
            _attestation.attestor,
            _task.msgValue,
            _task.policyID,
            _task.uuid,
            _task.expiration
        );

        return true;
    }
}
