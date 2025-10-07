// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {IPredicateRegistry, Attestation, Statement} from "../interfaces/IPredicateRegistry.sol";
import "../interfaces/IPredicateClient.sol";

/**
 * @title PredicateClient
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice Abstract contract for integrating Predicate attestation validation
 * @dev Provides core functionality for contracts to validate attestations before executing transactions.
 *      Implements ERC-7201 namespaced storage to prevent collisions in upgradeable contracts.
 * 
 * Usage:
 * 1. Inherit this contract
 * 2. Call _initPredicateClient() in your constructor
 * 3. Use _authorizeTransaction() to validate attestations before business logic
 * 
 * Example:
 * ```solidity
 * contract MyContract is PredicateClient {
 *     constructor(address _registry, string memory _policy) {
 *         _initPredicateClient(_registry, _policy);
 *     }
 *     
 *     function protectedFunction(Attestation calldata _attestation) external {
 *         bytes memory encoded = abi.encodeWithSignature("_internal()");
 *         require(_authorizeTransaction(_attestation, encoded, msg.sender, msg.value));
 *         _internal();
 *     }
 * }
 * ```
 */
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

    /**
     * @notice Initializes the Predicate client with registry and policy ID
     * @dev Must be called in the constructor of the inheriting contract.
     *      Sets both the registry address and initial policy ID.
     * @param _registryAddress The address of the PredicateRegistry contract
     * @param _policyId The initial policy identifier for this contract (typically "x-{hash[:16]}")
     */
    function _initPredicateClient(address _registryAddress, string memory _policyId) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.registry = IPredicateRegistry(_registryAddress);
        _setPolicyId(_policyId);
    }

    /**
     * @notice Updates the policy ID for this contract
     * @dev Updates local storage and registers with PredicateRegistry.
     *      Should typically be restricted to owner/admin.
     * @param _policyId The new policy identifier to set
     */
    function _setPolicyId(
        string memory _policyId
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.policy = _policyId;
        $.registry.setPolicyId(_policyId);
    }

    function getPolicyId() external view returns (string memory policyId) {
        return _getPolicyId();
    }

    function _getPolicyId() internal view returns (string memory policyId) {
        return _getPredicateClientStorage().policy;
    }

    /**
     * @notice Updates the PredicateRegistry address
     * @dev Should typically be restricted to owner/admin for security.
     *      Does not re-register the policy - call _setPolicyId() if needed.
     * @param _registryAddress The new PredicateRegistry contract address
     * @custom:security Changing registry is sensitive - ensure proper access control
     */
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
     * @notice Validates a transaction by verifying the attestation
     * @dev Constructs a Statement from parameters and validates it against the attestation.
     *      This is the core authorization function that should be called before executing
     *      any protected business logic.
     * 
     * Process:
     * 1. Builds Statement struct with transaction parameters
     * 2. Calls PredicateRegistry.validateAttestation()
     * 3. Registry verifies signature and checks attestation validity
     * 4. Returns true if valid (reverts if invalid)
     * 
     * @param _attestation The attestation containing UUID, expiration, attester, and signature
     * @param _encodedSigAndArgs The encoded function signature and arguments (use abi.encodeWithSignature)
     * @param _msgSender The original transaction sender (typically msg.sender)
     * @param _msgValue The ETH value sent with the transaction (typically msg.value)
     * @return success Always returns true (reverts on validation failure)
     * 
     * @custom:security Always use this before executing protected functions
     * @custom:security Encode the internal function call, not the public one
     */
    function _authorizeTransaction(
        Attestation memory _attestation,
        bytes memory _encodedSigAndArgs,
        address _msgSender,
        uint256 _msgValue
    ) internal returns (bool success) {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        Statement memory statement = Statement({
            msgSender: _msgSender,
            target: address(this),
            msgValue: _msgValue,
            encodedSigAndArgs: _encodedSigAndArgs,
            policy: $.policy,
            expiration: _attestation.expiration,
            uuid: _attestation.uuid
        });
        return $.registry.validateAttestation(statement, _attestation);
    }
}
