// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Ownable2StepUpgradeable} from "openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IPredicateRegistry, Statement, Attestation} from "./interfaces/IPredicateRegistry.sol";

/**
 * @title PredicateRegistry
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice Core registry contract for managing attesters, policies, and validating attestations
 * @dev This contract provides:
 *      - Attester registration/deregistration (owner only)
 *      - Policy management (clients set their own policies)
 *      - Statement validation with attestation verification
 *      - UUID-based replay protection
 *      - ECDSA signature verification using OpenZeppelin
 * @custom:security Uses ERC-1967 upgradeable proxy pattern via Ownable2StepUpgradeable
 */
contract PredicateRegistry is IPredicateRegistry, Ownable2StepUpgradeable {
    // storage
    address[] public registeredAttesters;
    mapping(address => bool) public isAttesterRegistered;
    mapping(address => uint256) public attesterIndex;
    mapping(address => string) public clientToPolicy;
    mapping(string => bool) public usedStatementUUIDs;

    // events
    event AttesterRegistered(address indexed attester);
    event AttesterDeregistered(address indexed attester);
    event PolicySet(address indexed client, address indexed setter, string policy, uint256 timestamp);

    // statement validation event
    event StatementValidated(
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
     * @notice Registers a new attester who can sign attestations
     * @dev Only the contract owner can register attesters. Reverts if attester already registered.
     * @param _attester The address of the attester to register
     * @custom:security Attesters have critical trust - only register verified entities
     */
    function registerAttester(
        address _attester
    ) external onlyOwner {
        require(!isAttesterRegistered[_attester], "Predicate.registerAttester: attester already registered");
        attesterIndex[_attester] = registeredAttesters.length;
        registeredAttesters.push(_attester);
        isAttesterRegistered[_attester] = true;
        emit AttesterRegistered(_attester);
    }

    /**
     * @notice Removes an attester from the registry
     * @dev Only the contract owner can deregister attesters. 
     * @param _attester The address of the attester to remove
     * @custom:security Existing attestations from this attester remain valid until their expiration
     */
    function deregisterAttester(
        address _attester
    ) external onlyOwner {
        require(isAttesterRegistered[_attester], "Predicate.deregisterAttester: attester not registered");
        
        uint256 indexToRemove = attesterIndex[_attester];
        uint256 lastIndex = registeredAttesters.length - 1;
        
        if (indexToRemove != lastIndex) {
            address lastAttester = registeredAttesters[lastIndex];
            registeredAttesters[indexToRemove] = lastAttester;
            attesterIndex[lastAttester] = indexToRemove;
        }
        
        registeredAttesters.pop();
        delete attesterIndex[_attester];
        isAttesterRegistered[_attester] = false;
        emit AttesterDeregistered(_attester);
    }

    /**
     * @notice Returns the complete list of registered attesters
     * @dev Returns a dynamic array - may be gas-intensive for large attester sets
     * @return attesters Array of all currently registered attester addresses
     */
    function getRegisteredAttesters() external view returns (address[] memory attesters) {
        return registeredAttesters;
    }

    /**
     * @notice Sets or updates the policy ID for the calling contract/address
     * @dev Policy ID format:
     *      - Typically: "x-{hash(policy)[:16]}" (e.g., "x-a1b2c3d4e5f6g7h8")
     *      - Can be any string: IPFS CID, URL, or custom identifier
     *      - No format validation performed - accepts any string
     *      - Each client can only have one active policy ID at a time
     * @param _policyID The unique identifier for the policy to associate with msg.sender
     */
    function setPolicyID(
        string memory _policyID
    ) external {
        clientToPolicy[msg.sender] = _policyID;
        emit PolicySet(msg.sender, msg.sender, _policyID, block.timestamp);
    }

    /**
     * @notice Retrieves the policy ID associated with a specific client address
     * @param _client The address of the client to query
     * @return policyID The policy identifier, empty string if no policy set
     */
    function getPolicyID(
        address _client
    ) external view returns (string memory policyID) {
        return clientToPolicy[_client];
    }

    /**
     * @notice Computes the hash of a statement for attester signing
     * @dev Used by attesters to generate signatures. Includes target address (not msg.sender).
     *      This is the hash that attesters sign off-chain.
     * @param _statement The statement containing transaction details
     * @return digest The keccak256 hash of the encoded statement
     * @custom:security Attesters should sign this hash off-chain
     */
    function hashStatementWithExpiry(
        Statement calldata _statement
    ) public pure returns (bytes32 digest) {
        return keccak256(
            abi.encode(
                _statement.uuid,
                _statement.msgSender,
                _statement.target,
                _statement.msgValue,
                _statement.encodedSigAndArgs,
                _statement.policy,
                _statement.expiration
            )
        );
    }

    /**
     * @notice Computes statement hash with msg.sender for validation (prevents replay attacks)
     * @dev Used during validation. Replaces target with msg.sender to prevent cross-contract replay.
     *      This ensures the signature is only valid when called from the intended contract.
     * @param _statement The statement to hash
     * @return digest The keccak256 hash including msg.sender context
     * @custom:security Critical anti-replay measure - binds signature to calling contract
     */
    function hashStatementSafe(
        Statement calldata _statement
    ) public view returns (bytes32 digest) {
        return keccak256(
            abi.encode(
                _statement.uuid,
                _statement.msgSender,
                msg.sender,
                _statement.msgValue,
                _statement.encodedSigAndArgs,
                _statement.policy,
                _statement.expiration
            )
        );
    }

    /**
     * @notice Validates an attestation to authorize a transaction
     * @dev Performs comprehensive validation:
     *      1. Checks attestation has not expired (block.timestamp <= expiration)
     *      2. Verifies statement UUID hasn't been used (replay protection)
     *      3. Confirms UUID matches between statement and attestation
     *      4. Confirms expiration matches between statement and attestation
     *      5. Recovers signer from ECDSA signature using hashStatementSafe()
     *      6. Verifies recovered signer matches attestation.attester
     *      7. Confirms attester is registered
     *      8. Marks UUID as spent
     * @param _statement The statement describing the transaction to authorize
     * @param _attestation The signed attestation from an authorized attester
     * @return isVerified Always returns true (reverts on validation failure)
     * @custom:security Statement UUID is marked as spent to prevent replay attacks
     * @custom:security Uses msg.sender in hash to prevent cross-contract replay
     */
    function validateAttestation(
        Statement calldata _statement,
        Attestation calldata _attestation
    ) external returns (bool isVerified) {
        // check if attestation is expired or statement is already spent
        require(block.timestamp <= _attestation.expiration, "Predicate.validateAttestation: attestation expired");
        require(!usedStatementUUIDs[_statement.uuid], "Predicate.validateAttestation: statement UUID already used");

        // check if statement UUID matches attestation UUID and expiration
        require(
            keccak256(abi.encodePacked(_statement.uuid)) == keccak256(abi.encodePacked(_attestation.uuid)),
            "Predicate.validateAttestation: statement UUID does not match attestation UUID"
        );
        require(
            _statement.expiration == _attestation.expiration,
            "Predicate.validateAttestation: statement expiration does not match attestation expiration"
        );

        bytes32 messageHash = hashStatementSafe(_statement);
        address recoveredAttester = ECDSA.recover(messageHash, _attestation.signature);
        require(recoveredAttester == _attestation.attester, "Predicate.validateAttestation: Invalid signature");
        require(
            isAttesterRegistered[recoveredAttester],
            "Predicate.validateAttestation: Attester is not a registered attester"
        );

        usedStatementUUIDs[_statement.uuid] = true;

        emit StatementValidated(
            _statement.msgSender,
            _statement.target,
            _attestation.attester,
            _statement.msgValue,
            _statement.policy,
            _statement.uuid,
            _statement.expiration
        );

        return true;
    }
}
