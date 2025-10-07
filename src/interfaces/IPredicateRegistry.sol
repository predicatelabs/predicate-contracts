// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

/**
 * @notice Struct that bundles together a statement's parameters for validation
 * @dev A statement represents a claim or assertion about a transaction to be executed.
 *      It contains all the necessary information to validate that a transaction
 *      is authorized by an attester according to a specific policy.
 * @custom:security UUID must be unique per statement to prevent replay attacks
 */
struct Statement {
    // the unique identifier for the statement
    string uuid;
    // the address of the sender of the statement
    address msgSender;
    // the address of the target contract for the statement
    address target;
    // the value to send with the statement
    uint256 msgValue;
    // the encoded signature and arguments for the statement
    bytes encodedSigAndArgs;
    // the policy associated with the statement
    string policy;
    // the timestamp by which the statement must be executed
    uint256 expiration;
}

/**
 * @notice Struct that bundles together an attestation's parameters for validation
 * @dev An attestation is a signed approval from an authorized attester.
 *      The signature is created by signing the hash of the corresponding Statement.
 * @custom:security signature must be generated using hashStatementWithExpiry()
 */
struct Attestation {
    // the unique identifier for the attestation
    string uuid;
    // the timestamp by which the attestation must be executed
    uint256 expiration;
    // the address of the attester
    address attester;
    // the signature from the attestation
    bytes signature;
}

/**
 * @title IPredicateRegistry
 * @author Predicate Labs, Inc (https://predicate.io)
 * @notice Interface for the core registry managing attesters, policies, and statement validation
 * @dev Defines the contract interface for PredicateRegistry implementation
 */
interface IPredicateRegistry {
    /**
     * @notice Sets a policy for the sender, defining execution rules for statements
     * @dev Associates a policy identifier with msg.sender. Policy string can be:
     *      - IPFS CID (e.g., "QmX...")
     *      - URL (e.g., "https://example.com/policy")
     *      - Simple identifier (e.g., "policy-v1")
     * @param policy The unique identifier for the policy
     */
    function setPolicy(
        string memory policy
    ) external;

    /**
     * @notice Retrieves the policy associated with a client address
     * @param client The address to query
     * @return policy The policy identifier, empty string if none set
     */
    function getPolicy(
        address client
    ) external view returns (string memory policy);

    /**
     * @notice Validates an attestation to authorize a statement execution
     * @dev Verifies:
     *      - Attestation not expired
     *      - Statement UUID not previously used (replay protection)
     *      - UUIDs match between statement and attestation
     *      - Expirations match
     *      - Signature is valid (ECDSA recovery)
     *      - Attester is registered
     * @param _statement The statement to validate
     * @param _attestation The signed attestation authorizing the statement
     * @return isVerified True if valid, reverts otherwise
     * @custom:security Marks UUID as spent to prevent replay attacks
     */
    function validateAttestation(
        Statement memory _statement,
        Attestation memory _attestation
    ) external returns (bool isVerified);
}
