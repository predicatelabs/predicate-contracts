// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {IRateLimiter, RateLimitParams, TxHistory, TxBatch} from "../interfaces/IRateLimiter.sol";
import {IPriceAggregator} from "../interfaces/IPriceAggregator.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @title RateLimiter
 * @dev Implements a value-based rate limiting mechanism for ERC20 token transfers.
 *
 * This contract allows for the implementation of rate limits on token transfers
 * based on the total value of transactions within a specified time window. It uses
 * an external price oracle for accurate valuation of assets in a common denominator.
 *
 * The rate limiter can be integrated into token transfers, swaps, or any other
 * value transfer mechanism to provide an additional layer of control over individual
 * account inflows.
 *
 */
contract RateLimiter is IRateLimiter, Ownable {
    error PredicateClient_IsRateLimited();
    error RateLimiter_InvalidToken();
    error TokenNotSupported(address token);
    error InvalidMaxAmount(uint256 provided, uint256 minimum, uint256 maximum);
    error InvalidDuration(uint256 provided, uint256 minimum);
    error InvalidBatchSize(uint64 provided, uint64 minimum);

    uint256 private constant MIN_LIMIT_AMOUNT = 1e6;
    uint256 private constant MAX_LIMIT_AMOUNT = 1e12;
    uint256 private constant MIN_DURATION = 1;
    uint64 private constant MIN_BATCH_SIZE = 1;
    uint256 private constant MAX_PRECISION = 1e18;
    uint256 private constant USDC_PRECISION = 1e6;
    uint256 private constant MAX_DECIMALS = 18;
    uint256 private constant USDC_DECIMALS = 6;
    uint256 private constant SCALING_FACTOR = 10 ** (MAX_DECIMALS - USDC_DECIMALS);

    event RateLimitParamsUpdated(uint256 maxAmount, uint256 duration, uint64 batchSize);
    event RateLimitExceeded(address indexed user, address token, uint256 amount, uint256 limit);

    mapping(address => TxHistory) public txHistory;
    mapping(address => bool) public bypassRateLimit;

    bool public isRateLimiterEnabled;

    RateLimitParams public rateLimitParams;
    IPriceAggregator public priceOracle;

    using FixedPointMathLib for uint256;

    /**
     * @notice Retrieves the current rate limit parameters.
     * @return RateLimitParams struct containing the current rate limit settings.
     */
    function getRateLimitParams() external view returns (RateLimitParams memory) {
        return rateLimitParams;
    }

    /**
     * @notice Retrieves the transaction history for a specific user.
     * @param user The address of the user whose transaction history is requested.
     * @return TxHistory struct containing the user's transaction history.
     */
    function getTxHistory(
        address user
    ) external view returns (TxHistory memory) {
        return txHistory[user];
    }

    /**
     * @notice Sets new parameters for rate limiting.
     * @dev Only callable by the contract owner. Updates the rate limit parameters and enables the rate limiter.
     * @param params The new rate limit parameters to be set.
     */
    function setRateLimitParams(
        RateLimitParams calldata params
    ) external onlyOwner {
        if (params.maxAmount < MIN_LIMIT_AMOUNT || params.maxAmount > MAX_LIMIT_AMOUNT) {
            revert InvalidMaxAmount(params.maxAmount, MIN_LIMIT_AMOUNT, MAX_LIMIT_AMOUNT);
        }

        if (params.duration < MIN_DURATION) {
            revert InvalidDuration(params.duration, MIN_DURATION);
        }

        if (params.batchSize < MIN_BATCH_SIZE) {
            revert InvalidBatchSize(params.batchSize, MIN_BATCH_SIZE);
        }

        rateLimitParams = params;
        isRateLimiterEnabled = true;

        emit RateLimitParamsUpdated(params.maxAmount, params.duration, params.batchSize);
    }

    /**
     * @notice Enables rate limit bypass for a specific user.
     * @dev Only callable by the contract owner.
     * @param user The address of the user to bypass rate limiting for.
     */
    function setRateLimitBypass(
        address user
    ) external onlyOwner {
        bypassRateLimit[user] = true;
    }

    /**
     * @notice Removes rate limit bypass for a specific user.
     * @param user The address of the user to remove rate limiting bypass from.
     */
    function removeRateLimitBypass(
        address user
    ) external onlyOwner {
        bypassRateLimit[user] = false;
    }

    /**
     * @notice Sets the price oracle address.
     * @dev Only callable by the contract owner.
     * @param _priceOracle The address of the new price oracle contract.
     */
    function setPriceOracle(
        address _priceOracle
    ) external onlyOwner {
        priceOracle = IPriceAggregator(_priceOracle);
    }

    /**
     * @notice Enables the rate limiter.
     * @dev Only callable by the contract owner.
     */
    function enableRateLimiter() external onlyOwner {
        isRateLimiterEnabled = true;
    }

    /**
     * @notice Disables the rate limiter.
     * @dev Only callable by the contract owner.
     */
    function disableRateLimiter() external onlyOwner {
        isRateLimiterEnabled = false;
    }

    /**
     * @notice Evaluates whether a transaction exceeds the rate limit and updates the transaction history if it doesn't.
     * @param token The address of the token being transacted.
     * @param amount The amount of the token being transacted.
     * @return bool Returns true if the transaction is within the rate limit, false otherwise.
     */
    function evaluateRateLimit(address token, uint256 amount) external returns (bool) {
        return _evaluateRateLimit(token, amount);
    }

    function _evaluateRateLimit(address token, uint256 amount) internal returns (bool) {
        uint256 scaledAmount = amount.mulDivDown(SCALING_FACTOR, USDC_PRECISION);
        uint256 price = priceOracle.getPrice(token, amount);
        uint256 txAmount = scaledAmount.mulDivDown(price, MAX_PRECISION);
        uint256 maxAmount = rateLimitParams.maxAmount.mulDivDown(SCALING_FACTOR, USDC_PRECISION);
        (bool _exceedsLimit,) = _checkIfLimitExceeds(msg.sender, token, txAmount, maxAmount);
        if (_exceedsLimit) {
            emit RateLimitExceeded(msg.sender, token, amount, rateLimitParams.maxAmount);
            return false;
        }
        uint256 oldestRelevantBlock = _getOldestRelevantBlock(block.number);
        _setTotalActiveTxValue(oldestRelevantBlock);
        _updateTxHistory(block.number, txAmount);
        return true;
    }

    /**
     * @notice Checks if a potential transaction would exceed the rate limit without modifying state.
     * @param sender The address initiating the transaction.
     * @param token The address of the token being transacted.
     * @param amount The amount of the token being transacted.
     * @return bool Indicates whether the transaction would exceed the rate limit.
     * @return uint256 The remaining allowance for transactions within the current time window.
     */
    function checkIfLimitExceeds(address sender, address token, uint256 amount) external view returns (bool, uint256) {
        uint256 scaledAmount = amount.mulDivDown(SCALING_FACTOR, USDC_PRECISION);
        uint256 txAmount = scaledAmount.mulDivDown(priceOracle.getPrice(token, amount), MAX_PRECISION);
        uint256 maxAmount = rateLimitParams.maxAmount.mulDivDown(SCALING_FACTOR, USDC_PRECISION);
        return _checkIfLimitExceeds(sender, token, txAmount, maxAmount);
    }

    function _checkIfLimitExceeds(
        address sender,
        address token,
        uint256 txAmount,
        uint256 maxAmount
    ) internal view returns (bool, uint256) {
        if (!priceOracle.isTokenSupported(token)) {
            revert TokenNotSupported(token);
        }
        uint256 oldestRelevantBlock = _getOldestRelevantBlock(block.number);
        uint256 totalActiveTxValue = _getTotalActiveTxValue(sender, oldestRelevantBlock);
        uint256 remainingAllowance = _getRemainingAllowance(sender, totalActiveTxValue, txAmount, maxAmount);
        bool _exceeds = _exceedsRateLimit(sender, totalActiveTxValue, txAmount, maxAmount);

        return (_exceeds, remainingAllowance);
    }

    function _updateTxHistory(uint256 blockNumber, uint256 amount) internal {
        TxHistory storage history = txHistory[msg.sender];
        if (_shouldUpdateExistingBatch(history, blockNumber)) {
            _updateExistingBatch(history, amount);
        } else {
            _createNewBatch(history, blockNumber, amount);
        }
    }

    function _shouldUpdateExistingBatch(TxHistory storage history, uint256 blockNumber) private view returns (bool) {
        return
            history.txBatches.length > 0 && blockNumber < history.txBatches[history.txBatches.length - 1].endBlockNumber;
    }

    function _updateExistingBatch(TxHistory storage history, uint256 amount) private {
        history.txBatches[history.txBatches.length - 1].amount += amount;
        history.total += amount;
    }

    function _createNewBatch(TxHistory storage history, uint256 blockNumber, uint256 amount) private {
        TxBatch memory newTxBatch = TxBatch(amount, blockNumber, blockNumber + rateLimitParams.batchSize);
        history.txBatches.push(newTxBatch);
        history.total += amount;
    }

    function _setTotalActiveTxValue(
        uint256 oldestRelevantBlock
    ) internal {
        TxHistory storage history = txHistory[msg.sender];
        uint256 total = history.total;
        uint256 ptr = history.ptr;
        while (ptr < history.txBatches.length && history.txBatches[ptr].endBlockNumber <= oldestRelevantBlock) {
            total -= history.txBatches[ptr].amount;
            ptr++;
        }
        history.total = total;
        history.ptr = ptr;
    }

    function _getTotalActiveTxValue(address sender, uint256 oldestRelevantBlock) internal view returns (uint256) {
        TxHistory memory history = txHistory[sender];

        if (history.txBatches.length == 0) {
            return 0;
        }

        uint256 total = history.total;
        uint256 ptr = history.ptr;
        while (ptr < history.txBatches.length && history.txBatches[ptr].endBlockNumber < oldestRelevantBlock) {
            total -= history.txBatches[ptr].amount;
            ptr++;
        }
        return total;
    }

    /**
     * @notice Retrieves the transaction batch at the current pointer for a given user.
     * @param user The address of the user to check.
     * @return amount The total amount in the batch.
     * @return startBlockNumber The starting block number of the batch.
     * @return endBlockNumber The ending block number of the batch.
     */
    function getTxBatchAtPtr(
        address user
    ) external view returns (uint256 amount, uint256 startBlockNumber, uint256 endBlockNumber) {
        TxHistory memory history = txHistory[user];
        TxBatch memory batch = history.txBatches[history.ptr];
        return (batch.amount, batch.startBlockNumber, batch.endBlockNumber);
    }

    function _getOldestRelevantBlock(
        uint256 blockNumber
    ) private view returns (uint256) {
        return blockNumber < rateLimitParams.duration ? 0 : blockNumber - rateLimitParams.duration;
    }

    function _exceedsRateLimit(
        address sender,
        uint256 totalActiveTxValue,
        uint256 txAmount,
        uint256 maxAmount
    ) internal view returns (bool) {
        return !bypassRateLimit[sender] && totalActiveTxValue + txAmount > maxAmount;
    }

    function _getRemainingAllowance(
        address sender,
        uint256 total,
        uint256 amount,
        uint256 maxAmount
    ) internal view returns (uint256) {
        if (bypassRateLimit[sender]) {
            return maxAmount;
        }

        if (total + amount <= maxAmount) {
            return maxAmount - total - amount;
        }

        return maxAmount - total;
    }
}
