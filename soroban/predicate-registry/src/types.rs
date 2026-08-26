use soroban_sdk::{contracterror, contracttype, Address, Bytes, BytesN, String};

/// Describes a transaction to be authorized. Mirrors the EVM Statement struct.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Statement {
    pub uuid: String,
    pub msg_sender: Address,
    pub target: Address,
    pub msg_value: i128,
    /// Raw call data or a hash of it; the attester signs whichever is supplied.
    pub encoded_sig_and_args: Bytes,
    /// Policy identifier, e.g. "x-a1b2c3d4e5f6g7h8".
    pub policy: String,
    /// Ledger timestamp, in seconds.
    pub expiration: u64,
}

/// Ed25519-signed authorization. `uuid` and `expiration` must match the statement's.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Attestation {
    pub uuid: String,
    pub expiration: u64,
    pub attester: BytesN<32>,
    pub signature: BytesN<64>,
}

// Switch events().publish() to #[contractevent] once the SDK supports it; 23.5.3 does not.

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
    /// Contract has not been initialized
    NotInitialized = 8,
}
