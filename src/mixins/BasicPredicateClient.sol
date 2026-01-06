// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IPredicateRegistry, Attestation, Statement} from "../interfaces/IPredicateRegistry.sol";
import {IPredicateClient, PredicateClient__Unauthorized} from "../interfaces/IPredicateClient.sol";

/**
 * @title BasicPredicateClient
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice Simplified authorization for WHO-based policies only
 * @dev Use when policies only validate sender identity, not function or value details.
 *      Uses canonical zero values for encodedSigAndArgs and msgValue.
 */
abstract contract BasicPredicateClient is IPredicateClient {
    /// @notice Struct to contain stateful values for PredicateClient-type contracts
    /// @custom:storage-location erc7201:predicate.storage.PredicateClient
    struct PredicateClientStorage {
        IPredicateRegistry registry;
        string policy;
    }

    /// @notice The storage slot for the PredicateClientStorage struct
    /// @dev keccak256(abi.encode(uint256(keccak256("predicate.storage.PredicateClient")) - 1)) & ~bytes32(uint256(0xff))
    /// @dev Same slot as PredicateClient for consistency across implementations
    bytes32 private constant _PREDICATE_CLIENT_STORAGE_SLOT =
        0x804776a84f3d03ad8442127b1451e2fbbb6a715c681d6a83c9e9fca787b99300;

    /// @notice Emitted when the PredicateRegistry address is updated
    event PredicateRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /// @notice Emitted when the policy ID is updated
    event PredicatePolicyIDUpdated(string oldPolicyID, string newPolicyID);

    function _getPredicateClientStorage() private pure returns (PredicateClientStorage storage $) {
        assembly {
            $.slot := _PREDICATE_CLIENT_STORAGE_SLOT
        }
    }

    /**
     * @notice Initializes with registry and policy ID
     * @dev Must be called in constructor
     */
    function _initPredicateClient(
        address _registryAddress,
        string memory _policyID
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.registry = IPredicateRegistry(_registryAddress);
        _setPolicyID(_policyID);
    }

    /// @notice Updates the policy ID
    function _setPolicyID(
        string memory _policyID
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        string memory oldPolicyID = $.policy;

        if (keccak256(bytes(oldPolicyID)) != keccak256(bytes(_policyID))) {
            $.policy = _policyID;
            $.registry.setPolicyID(_policyID);
            emit PredicatePolicyIDUpdated(oldPolicyID, _policyID);
        }
    }

    /// @notice Updates the registry address
    function _setRegistry(
        address _registryAddress
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        address oldRegistry = address($.registry);

        if (oldRegistry != _registryAddress) {
            $.registry = IPredicateRegistry(_registryAddress);

            // Re-register cached policy with new registry
            string memory cachedPolicy = $.policy;
            if (bytes(cachedPolicy).length > 0) {
                $.registry.setPolicyID(cachedPolicy);
            }

            emit PredicateRegistryUpdated(oldRegistry, _registryAddress);
        }
    }

    /// @notice Returns the policy ID
    function getPolicyID() external view returns (string memory policyID) {
        return _getPolicyID();
    }

    function _getPolicyID() internal view returns (string memory policyID) {
        return _getPredicateClientStorage().policy;
    }

    /// @notice Returns the registry address
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
     * @notice Validates transaction with canonical zero values
     * @dev Uses canonical msgValue=0 and encodedSigAndArgs="" for simple WHO-based validation
     */
    function _authorizeTransaction(
        Attestation memory _attestation,
        address _msgSender
    ) internal returns (bool success) {
        PredicateClientStorage storage $ = _getPredicateClientStorage();

        // Build Statement with canonical zero values
        Statement memory statement = Statement({
            msgSender: _msgSender,
            target: address(this),
            msgValue: 0, // Canonical zero for value
            encodedSigAndArgs: hex"", // Canonical empty bytes for function data
            policy: $.policy,
            expiration: _attestation.expiration,
            uuid: _attestation.uuid
        });

        return $.registry.validateAttestation(statement, _attestation);
    }
}
