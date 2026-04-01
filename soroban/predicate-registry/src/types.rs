use soroban_sdk::{contracterror, contracttype, Address, BytesN, String};

/// Mirrors the EVM Statement struct.
/// Describes a transaction to be authorized.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Statement {
    /// Unique identifier — replay protection key
    pub uuid: String,
    /// Original transaction sender
    pub msg_sender: Address,
    /// Target contract address
    pub target: Address,
    /// Encoded function call data
    pub encoded_sig_and_args: BytesN<32>,
    /// Policy identifier (e.g. "x-a1b2c3d4e5f6g7h8")
    pub policy: String,
    /// Deadline ledger timestamp
    pub expiration: u64,
}

/// Ed25519-signed authorization from an attester.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Attestation {
    /// Must match Statement.uuid
    pub uuid: String,
    /// Must match Statement.expiration
    pub expiration: u64,
    /// Ed25519 public key of the attester (32 bytes)
    pub attester: BytesN<32>,
    /// Ed25519 signature (64 bytes)
    pub signature: BytesN<64>,
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum RegistryError {
    /// Caller is not the contract owner
    Unauthorized = 1,
    /// Attester is already registered
    AttesterAlreadyRegistered = 2,
    /// Attester is not registered
    AttesterNotRegistered = 3,
    /// Attestation has expired
    AttestationExpired = 4,
    /// Statement UUID has already been spent
    UuidAlreadyUsed = 5,
    /// Statement/Attestation UUID mismatch
    UuidMismatch = 6,
    /// Statement/Attestation expiration mismatch
    ExpirationMismatch = 7,
    /// Ed25519 signature verification failed
    InvalidSignature = 8,
    /// Contract has not been initialized
    NotInitialized = 9,
    /// Contract has already been initialized
    AlreadyInitialized = 10,
}
