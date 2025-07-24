// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IPredicateRegistry, Task, Attestation} from "./interfaces/IPredicateRegistry.sol";

/**
 * @title PredicateRegistry
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice This contract is a registry for policies, attestors and enables task validation.
 */
contract PredicateRegistry is IPredicateRegistry, Initializable, Ownable2StepUpgradeable {
    // storage
    string[] public enabledPolicies;
    address[] public registeredAttestors;
    mapping(address => bool) public isRegisteredAttestor;
    mapping(string => bool) public isEnabledPolicy;
    mapping(address => string) public clientToPolicy;
    mapping(string => bool) public spentTaskIDs;

    // events
    event PolicyEnabled(string policy);
    event PolicyDisabled(string policy);
    event AttestorRegistered(address indexed attestor);
    event AttestorDeregistered(address indexed attestor);
    event PolicySet(address indexed client, address indexed setter, string policy, uint256 timestamp);

    // task validation event
    event TaskValidated(
        address indexed msgSender,
        address indexed target,
        address indexed attestor,
        uint256 msgValue,
        string policy,
        string uuid,
        uint256 expiration
    );

    /**
     * @notice Initializes the contract
     * @param _owner the address of the owner of the contract
     */
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
        registeredAttestors.push(_attestor);
        isRegisteredAttestor[_attestor] = true;
        emit AttestorRegistered(_attestor);
    }

    /**
     * @notice Deregisters an attestor
     * @param _attestor the address of the attestor to be deregistered
     */
    function deregisterAttestor(
        address _attestor
    ) external onlyOwner {
        require(isRegisteredAttestor[_attestor], "Predicate.deregisterAttestor: attestor not registered");
        for (uint256 i = 0; i < registeredAttestors.length; i++) {
            if (registeredAttestors[i] == _attestor) {
                registeredAttestors[i] = registeredAttestors[registeredAttestors.length - 1];
                registeredAttestors.pop();
                break;
            }
        }
        isRegisteredAttestor[_attestor] = false;
        emit AttestorDeregistered(_attestor);
    }

    /**
     * @notice Enables a policy for which clients can use
     * @param _policy is a unique identifier
     */
    function enablePolicy(
        string memory _policy
    ) external onlyOwner {
        require(!isEnabledPolicy[_policy], "Predicate.enablePolicy: policy already exists");
        isEnabledPolicy[_policy] = true;
        enabledPolicies.push(_policy);
        emit PolicyEnabled(_policy);
    }

    /**
     * @notice Disables a policy for which clients can use
     * @param _policy is a unique identifier
     */
    function disablePolicy(
        string memory _policy
    ) external onlyOwner {
        require(isEnabledPolicy[_policy], "Predicate.disablePolicy: policy doesn't exist");
        for (uint256 i = 0; i < enabledPolicies.length; i++) {
            if (keccak256(abi.encodePacked(enabledPolicies[i])) == keccak256(abi.encodePacked(_policy))) {
                enabledPolicies[i] = enabledPolicies[enabledPolicies.length - 1];
                enabledPolicies.pop();
                break;
            }
        }
        isEnabledPolicy[_policy] = false;
        emit PolicyDisabled(_policy);
    }

    /**
     * @notice Gets array of enabled policies
     * @return array of enabled policies
     */
    function getEnabledPolicies() external view returns (string[] memory) {
        return enabledPolicies;
    }

    /**
     * @notice Gets array of registered attestors
     * @return array of registered attestors
     */
    function getRegisteredAttestors() external view returns (address[] memory) {
        return registeredAttestors;
    }

    /**
     * @notice Overrides the policy for a client
     * @param _policy is the unique identifier for the policy
     * @param _client is the address of the client for which the policy is being overridden
     */
    function overrideClientPolicy(string memory _policy, address _client) external onlyOwner() {
        require(isEnabledPolicy[_policy], "Predicate.overrideClientPolicy: policy doesn't exist");
        require(clientToPolicy[_client] != _policy, "Predicate.overrideClientPolicy: client already has this policy");
        clientToPolicy[_client] = _policy;
        emit PolicySet(_client, msg.sender, _policy, block.timestamp);
    }

    /**
     * @notice Sets the policy for a client
     * @param _policy is the unique identifier for the policy
     */
    function setPolicy(string memory _policy) external {
        require(isEnabledPolicy[_policy], "Predicate.setPolicy: policy doesn't exist or is disabled");
        clientToPolicy[msg.sender] = _policy;
        emit PolicySet(msg.sender, msg.sender, _policy, block.timestamp);
    }

    /**
     * @notice Gets the policy for a client
     * @param _client is the address of the client for which the policy is being retrieved
     */
    function getPolicy(address _client) external view returns (string memory) {
        return clientToPolicy[_client];
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
                _task.policy,
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
                _task.policy,
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
        require(isRegisteredAttestor[recoveredAttestor], "Predicate.validateAttestation: Attestor is not a registered attestor");

        spentTaskIDs[_task.uuid] = true;

        emit TaskValidated(
            _task.msgSender,
            _task.target,
            _attestation.attestor,
            _task.msgValue,
            _task.policy,
            _task.uuid,
            _task.expiration
        );

        return true;
    }
}
