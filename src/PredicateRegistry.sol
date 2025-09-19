// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IPredicateRegistry, Task, Attestation} from "./interfaces/IPredicateRegistry.sol";

/**
 * @title PredicateRegistry
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice This contract is a registry for policies, attesters and enables task validation.
 */
contract PredicateRegistry is IPredicateRegistry, Ownable2StepUpgradeable {
    // storage
    address[] public registeredAttesters;
    mapping(address => bool) public isAttesterRegistered;
    mapping(address => string) public clientToPolicy;
    mapping(string => bool) public spentTaskIDs;

    // events
    event AttesterRegistered(address indexed attester);
    event AttesterDeregistered(address indexed attester);
    event PolicySet(address indexed client, address indexed setter, string policy, uint256 timestamp);

    // task validation event
    event TaskValidated(
        address indexed msgSender,
        address indexed target,
        address indexed attester,
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
     * @notice Registers a new attester
     * @param _attester the address of the attester to be registered
     */
    function registerAttester(
        address _attester
    ) external onlyOwner {
        require(!isAttesterRegistered[_attester], "Predicate.registerAttester: attester already registered");
        registeredAttesters.push(_attester);
        isAttesterRegistered[_attester] = true;
        emit AttesterRegistered(_attester);
    }

    /**
     * @notice Deregisters an attester
     * @param _attester the address of the attester to be deregistered
     */
    function deregisterAttester(
        address _attester
    ) external onlyOwner {
        require(isAttesterRegistered[_attester], "Predicate.deregisterAttester: attester not registered");
        for (uint256 i = 0; i < registeredAttesters.length; i++) {
            if (registeredAttesters[i] == _attester) {
                registeredAttesters[i] = registeredAttesters[registeredAttesters.length - 1];
                registeredAttesters.pop();
                break;
            }
        }
        isAttesterRegistered[_attester] = false;
        emit AttesterDeregistered(_attester);
    }

    /**
     * @notice Gets array of registered attesters
     * @return array of registered attesters
     */
    function getRegisteredAttesters() external view returns (address[] memory) {
        return registeredAttesters;
    }

    /**
     * @notice Sets the policy for a client
     * @param _policy is the unique identifier for the policy
     */
    function setPolicy(
        string memory _policy
    ) external {
        clientToPolicy[msg.sender] = _policy;
        emit PolicySet(msg.sender, msg.sender, _policy, block.timestamp);
    }

    /**
     * @notice Gets the policy for a client
     * @param _client is the address of the client for which the policy is being retrieved
     */
    function getPolicy(
        address _client
    ) external view returns (string memory) {
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
     * @param _attestation the attestation from the attester
     */
    function validateAttestation(
        Task calldata _task,
        Attestation calldata _attestation
    ) external returns (bool isVerified) {
        // check if attestation is expired or task is already spent
        require(block.timestamp <= _attestation.expiration, "Predicate.validateAttestation: attestation expired");
        require(!spentTaskIDs[_task.uuid], "Predicate.validateAttestation: task ID already spent");

        // check if task ID matches attestation ID and expiration
        require(
            keccak256(abi.encodePacked(_task.uuid)) == keccak256(abi.encodePacked(_attestation.uuid)),
            "Predicate.validateAttestation: task ID does not match attestation ID"
        );
        require(
            _task.expiration == _attestation.expiration,
            "Predicate.validateAttestation: task expiration does not match attestation expiration"
        );

        bytes32 messageHash = hashTaskSafe(_task);
        address recoveredAttester = ECDSA.recover(messageHash, _attestation.signature);
        require(recoveredAttester == _attestation.attester, "Predicate.validateAttestation: Invalid signature");
        require(
            isAttesterRegistered[recoveredAttester],
            "Predicate.validateAttestation: Attester is not a registered attester"
        );

        spentTaskIDs[_task.uuid] = true;

        emit TaskValidated(
            _task.msgSender,
            _task.target,
            _attestation.attester,
            _task.msgValue,
            _task.policy,
            _task.uuid,
            _task.expiration
        );

        return true;
    }
}
