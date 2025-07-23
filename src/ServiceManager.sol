// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IPredicateRegistry, Task, Attestation} from "./interfaces/IPredicateRegistry.sol";

contract PredicateRegistry is IPredicateRegistry, Initializable, Ownable2StepUpgradeable {
    error PredicateRegistryUnauthorized();

    string[] public enabledPolicyIDs;
    mapping(address => bool) public registeredAttestors;
    mapping(string => bool) public isEnabledPolicyID;
    mapping(address => string) public clientToPolicyID;
    mapping(string => bool) public spentTaskIDs;

    event PolicyEnabled(string policyID);
    event PolicyDisabled(string policyID);
    event AttestorRegistered(address indexed attestor);
    event AttestorDeregistered(address indexed attestor);
    event PolicyIDOverridden(address indexed client, string policyID);

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
     * @notice Registers a new attestor
     * @param _attestor the address of the attestor to be registered
     */
    function registerAttestor(
        address _attestor
    ) external onlyOwner {
        require(!registeredAttestors[_attestor], "Predicate.registerAttestor: attestor already registered");
        registeredAttestors[_attestor] = true;
        emit AttestorRegistered(_attestor);
    }


    /**
     * @notice Deregisters an attestor
     * @param _attestor the address of the attestor to be deregistered
     */
    function deregisterAttestor(
        address _attestor
    ) external onlyOwner {
        require(registeredAttestors[_attestor], "Predicate.deregisterAttestor: attestor not registered");
        registeredAttestors[_attestor] = false;
        emit AttestorDeregistered(_attestor);
    }

    /**
     * @notice Enables a policy for which clients can use
     * @param _policyID is a unique identifier
     */
    function enablePolicy(
        string memory _policyID
    ) external onlyOwner {
        require(!isEnabledPolicyID[_policyID], "Predicate.enablePolicy: policy already exists");
        isEnabledPolicyID[_policyID] = true;
        enabledPolicyIDs.push(_policyID);
        emit PolicyEnabled(_policyID);
    }

    /**
     * @notice Gets array of enabled policy IDs
     * @return array of enabled policy IDs
     */
    function getEnabledPolicyIDs() external view returns (string[] memory) {
        return enabledPolicyIDs;
    }

    /**
     * @notice Disables a policy for which clients can use
     * @param _policyID is a unique identifier
     */
    function disablePolicy(
        string memory _policyID
    ) external {
        require(isEnabledPolicyID[_policyID], "Predicate.disablePolicy: policy ID doesn't exist");
        for (uint256 i = 0; i < enabledPolicyIDs.length; i++) {
            if (keccak256(abi.encodePacked(enabledPolicyIDs[i])) == keccak256(abi.encodePacked(_policyID))) {
                enabledPolicyIDs[i] = enabledPolicyIDs[enabledPolicyIDs.length - 1];
                enabledPolicyIDs.pop();
                break;
            }
        }
        isEnabledPolicyID[_policyID] = false;
        emit PolicyDisabled(_policyID);
    }

    /**
     * @notice Overrides the policy ID for a client
     * @param _policyID is the unique identifier for the policy
     * @param _clientAddress is the address of the client for which the policy is being overridden
     */
    function overrideClientPolicyID(string memory _policyID, address _clientAddress) external onlyOwner() {
        require(isEnabledPolicyID[_policyID], "Predicate.overrideClientPolicyID: policy ID doesn't exist");
        require(clientToPolicyID[_clientAddress] != _policyID, "Predicate.overrideClientPolicyID: client already has this policy ID");
        clientToPolicyID[_clientAddress] = _policyID;
        emit PolicyIDOverridden(_clientAddress, _policyID);
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
                _task.uuid,
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
                _task.uuid,
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
