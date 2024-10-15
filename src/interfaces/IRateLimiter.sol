// SPDX-License-Identifier: MIT

pragma solidity =0.8.12;

/// @title Rate Limit Parameters
/// @notice Struct to hold parameters for rate limiting transactions
struct RateLimitParams {
    /// @notice Maximum amount allowed, in USDC (scaled by 1e6) for precision
    uint256 maxAmount;
    /// @notice Duration of the rate limit window, in blocks
    uint256 duration;
    /// @notice The number of blocks in a transaction info batch
    uint64 batchSize;
}

/// @title Transaction Batch
/// @notice Represents an aggregate of transaction amounts based on block number
struct TxBatch {
    /// @notice The aggregate of transactions in this block range
    uint256 amount;
    /// @notice The block number for the start of the batch
    uint256 startBlockNumber;
    /// @notice The block number for the end of the batch
    uint256 endBlockNumber;
}

/// @title Transaction History
/// @notice Holds the transaction history for a user
struct TxHistory {
    /// @notice The cumulative total of all batches from the pointer to the end of the txBatches array
    uint256 total;
    /// @notice Pointer to a txBatch in the txBatches array, used to evaluate the total and find the first non-expired tx
    uint256 ptr;
    /// @notice Collection of txBatches for each user
    TxBatch[] txBatches;
}

interface IRateLimiter {
    /**
     * @notice Sets the rate limit parameters for the calling address.
     * @param params the rate limit parameters to be set
     * @dev This function sets the rate limit parameters for the calling address.
     */
    function setRateLimitParams(
        RateLimitParams calldata params
    ) external;

    /**
     * @notice Gets Txn batch at pointer for the calling address
     * @param user is the address of the user to be evaluated
     * @dev This function gets Txn batch at pointer for the calling address
     * @dev Fails when pointer is out of bounds
     */
    function getTxBatchAtPtr(
        address user
    ) external view returns (uint256 amount, uint256 startBlockNumber, uint256 endBlockNumber);

    /**
     * @notice Sets the price oracle for the calling address.
     * @param _priceOracle the price oracle to be set
     * @dev This function sets the price oracle for the calling address
     */
    function setPriceOracle(
        address _priceOracle
    ) external;

    /**
     * @notice Enables the rate limiter for the calling address.
     * @dev This function enables the rate limiter for the calling address
     */
    function enableRateLimiter() external;

    /**
     * @notice Disables the rate limiter for the calling address.
     * @dev This function disables the rate limiter for the calling address
     */
    function disableRateLimiter() external;

    /**
     * @notice Bypasses the rate limiter for the calling address.
     * @param user is the address of the user to be evaluated
     * @dev This function bypasses the rate limiter for the calling address
     */
    function setRateLimitBypass(
        address user
    ) external;

    /**
     * @notice Removes the rate limiter bypass for the calling address.
     * @param user is the address of the user to be evaluated
     * @dev This function removes the rate limiter bypass for the calling address
     */
    function removeRateLimitBypass(
        address user
    ) external;

    /**
     * @notice Evaluates the USDC amount for tokens using token amount and the token ticker to determine if the transaction should be rate limited.
     * @dev also returns remaining amount that can be transacted
     * @param sender is the address of the sender to be evaluated
     * @param token is the address of the token to be evaluated
     * @param amount is the amount of tokens to be evaluated
     */
    function checkIfLimitExceeds(address sender, address token, uint256 amount) external view returns (bool, uint256);

    /**
     * @notice Evaluates the USDC amount for tokens using token amount and the token ticker to determine if the transaction should be rate limited.
     * @param token is the address of the token to be evaluated
     * @param amount is the amount of tokens to be evaluated
     */
    function evaluateRateLimit(address token, uint256 amount) external returns (bool);

    /**
     * @notice Returns the rate limit parameters for the calling address.
     * @dev This function returns the rate limit parameters for the calling address.
     */
    function getRateLimitParams() external view returns (RateLimitParams memory);

    /**
     * @notice Returns the historical transaction information for the calling address.
     * @param user is the address of the user to be evaluated
     * @dev This function returns the historical transaction information for the user address
     */
    function getTxHistory(
        address user
    ) external view returns (TxHistory memory);
}
