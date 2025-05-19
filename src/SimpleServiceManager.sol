// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {Task, SignatureWithSaltAndExpiry} from "./interfaces/IPredicateManager.sol";
import {ISimpleServiceManager} from "./interfaces/ISimpleServiceManager.sol";

contract SimpleServiceManager is ISimpleServiceManager, Initializable, Ownable2StepUpgradeable {
    /**
     * @notice Emitted when a policy is set for a client
     */
    event SetPolicy(address indexed client, string indexed policyID);

    /**
     * @notice Emitted when a new policy is successfully synced
     */
    event PolicySynced(string indexed policyID);

    /**
     * @notice Emitted when a policy sync is skipped due to existing registration
     */
    event PolicySyncSkipped(string indexed policyID);

    /**
     * @notice Emitted when a new operator is registered
     */
    event OperatorRegistered(address indexed operator);

    /**
     * @notice Emitted when an operator is removed
     */
    event OperatorRemoved(address indexed operator);

    /**
     * @notice Emitted when an operator's signing key is updated
     */
    event OperatorUpdated(address indexed operator, address indexed signingKey);

    /**
     * @notice Emitted when a task is successfully validated
     */
    event TaskValidated(
        address indexed msgSender,
        address indexed target,
        uint256 indexed value,
        string policyID,
        string taskId,
        uint256 quorumThresholdCount,
        uint256 expireByTime,
        address[] signerAddresses
    );

    /// @dev Set of currently registered operator addresses
    EnumerableSet.AddressSet private registeredOperators;

    /// @notice Maps a signing key to its associated registration key (operator address)
    mapping(address => address) public signingKeyToRegistrationKey;

    /// @notice Maps a registration key (operator address) to its associated signing key
    mapping(address => address) public registrationKeyToSigningKey;

    /// @notice Tracks spent task IDs to prevent replay attacks
    mapping(string => bool) public spentTaskIDs;

    /// @notice Maps client contract addresses to their assigned policy ID
    mapping(address => string) public clientToPolicyID;

    /// @notice Maps policy IDs to their configured quorum threshold
    mapping(string => uint256) public policyIDToThreshold;

    /// @notice List of all deployed policy IDs
    string[] public deployedPolicyIDs;

    /**
     * @notice Initializes the contract and transfers ownership.
     * @param _owner Address to set as the contract owner.
     */
    function initialize(
        address _owner
    ) external initializer {
        __Ownable2Step_init();
        __Ownable_init(_owner);
    }

    /**
     * @notice Registers, updates, or removes operators and their signing keys
     * @param _registrationKeys Array of operator addresses to register or update
     * @param _signingKeys Corresponding signing keys for the operators
     * @param _removeOperators Array of operator addresses to remove
     */
    function syncOperators(
        address[] calldata _registrationKeys,
        address[] calldata _signingKeys,
        address[] calldata _removeOperators
    ) external onlyOwner {
        require(
            _registrationKeys.length == _signingKeys.length,
            "Predicate.syncOperators: registration and signing keys length mismatch"
        );

        // remove operators
        for (uint256 i = 0; i < _removeOperators.length;) {
            address operator = _removeOperators[i];
            if (EnumerableSet.contains(registeredOperators, operator)) {
                EnumerableSet.remove(registeredOperators, operator);
                address signingKey = registrationKeyToSigningKey[operator]; // get the signing key for the operator
                delete signingKeyToRegistrationKey[signingKey];
                delete registrationKeyToSigningKey[operator];
                emit OperatorRemoved(operator);
            }
            unchecked {
                ++i;
            }
        }

        // add or update operators
        for (uint256 i = 0; i < _registrationKeys.length;) {
            address operator = _registrationKeys[i];
            address signingKey = _signingKeys[i];

            bool isExistingOperator = EnumerableSet.contains(registeredOperators, operator);

            // if the operator is already registered, update the signing key and emit an event
            if (isExistingOperator) {
                if (registrationKeyToSigningKey[operator] != signingKey) {
                    address oldSigningKey = registrationKeyToSigningKey[operator];
                    delete signingKeyToRegistrationKey[oldSigningKey];
                    signingKeyToRegistrationKey[signingKey] = operator;
                    registrationKeyToSigningKey[operator] = signingKey;
                    emit OperatorUpdated(operator, signingKey);
                }
                unchecked {
                    ++i;
                }
                continue;
            }

            // if the operator is not registered, add it to the set and emit an event
            EnumerableSet.add(registeredOperators, operator);
            signingKeyToRegistrationKey[signingKey] = operator;
            registrationKeyToSigningKey[operator] = signingKey;
            emit OperatorRegistered(operator);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns all deployed policy IDs
     * @return Array of deployed policy IDs
     */
    function getDeployedPolicyIDs() external view returns (string[] memory) {
        return deployedPolicyIDs;
    }

    /**
     * @notice Registers policy IDs with their associated quorum thresholds
     * @param policyIDs Array of policy identifiers
     * @param thresholds Corresponding quorum thresholds for each policy
     */
    function syncPolicies(string[] calldata policyIDs, uint32[] calldata thresholds) external onlyOwner {
        require(
            policyIDs.length == thresholds.length, "Predicate.syncPolicies: policy IDs and thresholds length mismatch"
        );

        for (uint256 i = 0; i < policyIDs.length;) {
            require(bytes(policyIDs[i]).length > 0, "Predicate.syncPolicies: policy ID cannot be empty");
            require(thresholds[i] > 0, "Predicate.syncPolicies: threshold must be greater than zero");
            require(bytes(policyIDs[i]).length > 0, "Predicate.syncPolicies: policyID cannot be empty");

            if (policyIDToThreshold[policyIDs[i]] == 0) {
                policyIDToThreshold[policyIDs[i]] = thresholds[i];
                deployedPolicyIDs.push(policyIDs[i]);
                emit PolicySynced(policyIDs[i]);
            }

            emit PolicySyncSkipped(policyIDs[i]);
            unchecked {
                ++i;
            }
        }
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
        require(policyIDToThreshold[_policyID] > 0, "Predicate.setPolicy: policy ID not registered");
        clientToPolicyID[msg.sender] = _policyID;
        emit SetPolicy(msg.sender, _policyID);
    }

    /**
     * @notice Overrides the policy for a specific client address
     * @param _policyID is the unique identifier for the policy
     * @param _clientAddress is the address of the client for which the policy is being overridden
     */
    function overrideClientPolicyID(string memory _policyID, address _clientAddress) external onlyOwner {
        require(bytes(_policyID).length > 0, "Predicate.setPolicy: policy ID cannot be empty");
        clientToPolicyID[_clientAddress] = _policyID;
        emit SetPolicy(_clientAddress, _policyID);
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
                _task.value,
                _task.encodedSigAndArgs,
                _task.policyID,
                _task.quorumThresholdCount,
                _task.expireByTime
            )
        );
    }

    /**
     * @notice Validates signatures using the OpenZeppelin ECDSA library for the Predicate Single Transaction Model
     * @param _task the params of the task
     * @param  signerAddresses the addresses of the operators
     * @param  signatures the signatures of the operators
     */
    function validateSignatures(
        Task calldata _task,
        address[] memory signerAddresses,
        bytes[] memory signatures
    ) external returns (bool isVerified) {
        require(_task.quorumThresholdCount != 0, "Predicate.validateSignatures: quorum threshold count cannot be zero");
        require(
            signerAddresses.length == signatures.length,
            "Predicate.validateSignatures: Mismatch between signers and signatures"
        );
        require(block.timestamp <= _task.expireByTime, "Predicate.validateSignatures: transaction expired");
        require(!spentTaskIDs[_task.taskId], "Predicate.validateSignatures: task ID already spent");

        uint256 numSignaturesRequired = policyIDToThreshold[_task.policyID];
        require(
            numSignaturesRequired != 0 && _task.quorumThresholdCount == numSignaturesRequired,
            "Predicate.PredicateVerified: deployed policy quorum threshold differs from task quorum threshold"
        );

        bytes32 messageHash = hashTaskSafe(_task);
        for (uint256 i = 0; i < numSignaturesRequired;) {
            if (i > 0 && uint160(signerAddresses[i]) <= uint160(signerAddresses[i - 1])) {
                revert("Predicate.validateSignatures: Signer addresses must be unique and sorted");
            }
            address recoveredSigner = ECDSA.recover(messageHash, signatures[i]);
            require(recoveredSigner == signerAddresses[i], "Predicate.validateSignatures: Invalid signature");
            require(
                signingKeyToRegistrationKey[recoveredSigner] != address(0),
                "Predicate.validateSignatures: Signer is not a registered operator"
            );
            unchecked {
                ++i;
            }
        }

        emit TaskValidated(
            _task.msgSender,
            _task.target,
            _task.value,
            _task.policyID,
            _task.taskId,
            _task.quorumThresholdCount,
            _task.expireByTime,
            signerAddresses
        );

        spentTaskIDs[_task.taskId] = true;
        return true;
    }
}
