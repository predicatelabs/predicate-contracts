// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {Task, SignatureWithSaltAndExpiry} from "./interfaces/IPredicateManager.sol";
import {ISimpleServiceManager} from "./interfaces/ISimpleServiceManager.sol";

contract SimpleServiceManager is ISimpleServiceManager, Initializable, OwnableUpgradeable {
    event SetPolicy(address indexed client, string indexed policyID);
    event PolicySynced(string indexed policyID);
    event PolicySyncedSkipped(string indexed policyID);
    event OperatorRegistered(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event OperatorUpdated(address indexed operator, address indexed signingKey);

    event TaskValidated(
        address indexed msgSender,
        address indexed target,
        uint256 indexed value,
        string policyID,
        string taskId,
        uint256 quorumThresholdCount,
        uint256 expireByBlockNumber,
        address[] signerAddresses
    );

    EnumerableSet.AddressSet private registeredOperators;
    mapping(address => address) public signingKeyToOperatorAddress;
    mapping(address => address) public operatorAddressToSigningKey;

    mapping(string => bool) public spentTaskIDs;
    mapping(address => string) public clientToPolicyID;
    mapping(string => uint256) public policyIDToThreshold;
    string[] public deployedPolicyIDs;

    function initialize(
        address _owner
    ) external initializer {
        _transferOwnership(_owner);
    }

    /**
     * @notice Adds, deletes, or updates operator registration and signing keys
     * @param _registrationKeys is an array of registration keys for operators
     * @param _signingKeys is an array of signing keys corresponding to the registration keys
     * @param _removeOperators is an array of operator addresses to be removed
     */
    function syncOperators(address[] calldata _registrationKeys, address[] calldata _signingKeys, address[] calldata _removeOperators) external onlyOwner {
        require(
            _registrationKeys.length == _signingKeys.length,
            "Predicate.syncOperators: registration and signing keys length mismatch"
        );

        for (uint256 i = 0; i < _removeOperators.length;) {
            address operatorToRemove = _removeOperators[i];
            if (EnumerableSet.contains(registeredOperators, operatorToRemove)) {
                EnumerableSet.remove(registeredOperators, operatorToRemove);
                address signingKey = operatorAddressToSigningKey[operatorToRemove];
                delete signingKeyToOperatorAddress[signingKey];
                delete operatorAddressToSigningKey[operatorToRemove];
                emit OperatorRemoved(operatorToRemove);
            }
            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < _registrationKeys.length;) {
                address registrationKey = _registrationKeys[i];
                address signingKey = _signingKeys[i];

                bool isExistingOperator = EnumerableSet.contains(registeredOperators, registrationKey);

                if (isExistingOperator) {
                    if (operatorAddressToSigningKey[registrationKey] != signingKey) {
                        operatorAddressToSigningKey[registrationKey] = signingKey;
                        emit OperatorUpdated(registrationKey, signingKey);
                    }
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                EnumerableSet.add(registeredOperators, registrationKey);
                signingKeyToOperatorAddress[signingKey] = registrationKey;
                operatorAddressToSigningKey[registrationKey] = signingKey;
                emit OperatorRegistered(registrationKey);

                unchecked {
                    ++i;
            }
        }
    }

    /**
     * @notice Gets array of deployed policies
     * @return array of deployed policies
     */
    function getDeployedPolicyIDs() external view returns (string[] memory) {
        return deployedPolicyIDs;
    }

    /**
     * @notice Registers or updates policy IDs with their associated quorum thresholds
     * @dev Adds policies to the deployedPolicyIDs array and sets their thresholds
     * @param policyIDs Array of unique policy identifiers to register
     * @param thresholds Array of quorum thresholds corresponding to each policy ID
     */
    function syncPolicies(string[] calldata policyIDs, uint32[] calldata thresholds) external onlyOwner {
        require(
            policyIDs.length == thresholds.length,
            "Predicate.syncPolicies: policy IDs and thresholds length mismatch"
        );

        for (uint256 i = 0; i < policyIDs.length;) {
            require(bytes(policyIDs[i]).length > 0, "Predicate.syncPolicies: policy ID cannot be empty");
            require(thresholds[i] > 0, "Predicate.syncPolicies: threshold must be greater than zero");

            if (policyIDToThreshold[policyIDs[i]] == 0) {
                policyIDToThreshold[policyIDs[i]] = thresholds[i];
                deployedPolicyIDs.push(policyIDs[i]);
                emit PolicySynced(policyIDs[i]);
            }

            emit PolicySyncedSkipped(policyIDs[i]);
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
                _task.expireByBlockNumber
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
        require(block.number <= _task.expireByBlockNumber, "Predicate.validateSignatures: transaction expired");
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
                signingKeyToOperatorAddress[recoveredSigner] != address(0),
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
            _task.expireByBlockNumber,
            signerAddresses
        );

        spentTaskIDs[_task.taskId] = true;
        return true;
    }
}
