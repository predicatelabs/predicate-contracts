// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "../src/mixins/RateLimiter.sol";
import "./mocks/MockPriceAggregator.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract RateLimiterTest is Test {
    using FixedPointMathLib for uint256;

    address _token;
    uint256 _price;
    RateLimiter _rateLimiter;
    RateLimitParams _rateLimitParams;
    MockPriceAggregator _mockPriceAggregator;

    uint256 USDC_PRECISION = 1e6;
    uint256 USDC_SCALING_FACTOR = 1e12; // scaling 1e6 to 1e18
    uint256 MILLION_USDC = 1_000_000 * USDC_PRECISION;
    uint256 ETH_PRICE = 10 * USDC_PRECISION;

    function setUp() public {
        _token = address(0);
        _price = ETH_PRICE;
        _rateLimiter = new RateLimiter();
        _rateLimitParams = RateLimitParams({duration: 10, maxAmount: MILLION_USDC, batchSize: 5});
        _mockPriceAggregator = new MockPriceAggregator();
        _mockPriceAggregator.setPrice(_token, _price);
        _setPriceOracle(_mockPriceAggregator);
        _setRateLimitParams(_rateLimitParams);
    }

    function _setPriceOracle(
        MockPriceAggregator mpa
    ) private {
        _rateLimiter.setPriceOracle(address(mpa));
    }

    function _setRateLimitParams(
        RateLimitParams memory rlp
    ) private {
        require(rlp.duration > 0, "RateLimiterTest: duration must be greater than 0");
        require(rlp.maxAmount > 0, "RateLimiterTest: maxAmount must be greater than 0");
        require(rlp.batchSize > 0, "RateLimiterTest: batchSize must be greater than 0");
        _rateLimiter.setRateLimitParams(rlp);
    }

    function testSetRateLimitParams() public {
        RateLimitParams memory newParams = RateLimitParams({duration: 10, maxAmount: 2_000_000, batchSize: 3});
        _setRateLimitParams(newParams);
        RateLimitParams memory fetchedParams = _rateLimiter.getRateLimitParams();
        assertEq(fetchedParams.duration, newParams.duration);
        assertEq(fetchedParams.maxAmount, newParams.maxAmount);
        assertEq(fetchedParams.batchSize, newParams.batchSize);
        assertTrue(_rateLimiter.isRateLimiterEnabled());
    }

    function testIncorrectDurationRateLimitParams() public {
        vm.expectRevert();
        RateLimitParams memory newParams = RateLimitParams({duration: 0, maxAmount: 5, batchSize: 4});
        _setRateLimitParams(newParams);
    }

    function testIncorrectMaxAmtRateLimitParams() public {
        vm.expectRevert();
        RateLimitParams memory newParams = RateLimitParams({duration: 1, maxAmount: 0, batchSize: 4});
        _setRateLimitParams(newParams);
    }

    function testIncorrectBatchSizeRateLimitParams() public {
        vm.expectRevert();
        RateLimitParams memory newParams = RateLimitParams({duration: 1, maxAmount: 5, batchSize: 0});
        _setRateLimitParams(newParams);
    }

    function testEnableDisableRateLimiter() public {
        _rateLimiter.disableRateLimiter();
        assertFalse(_rateLimiter.isRateLimiterEnabled());
        _rateLimiter.enableRateLimiter();
        assertTrue(_rateLimiter.isRateLimiterEnabled());
    }

    function testSetPriceOracle() public {
        MockPriceAggregator newOracle = new MockPriceAggregator();
        _setPriceOracle(newOracle);
        assertEq(address(_rateLimiter.priceOracle()), address(newOracle));
    }

    function testGetPrice() public {
        MockPriceAggregator priceOracle = new MockPriceAggregator();
        address newToken = address(1);
        uint256 newPrice = 420;
        priceOracle.setPrice(newToken, newPrice);
        _setPriceOracle(priceOracle);

        assertEq(priceOracle.getPrice(newToken, 100), newPrice);
    }

    function testByPassRateLimit() public {
        assertFalse(_rateLimiter.bypassRateLimit(address(this)));
        _rateLimiter.setRateLimitBypass(address(this));
        assertTrue(_rateLimiter.bypassRateLimit(address(this)));
        _rateLimiter.removeRateLimitBypass(address(this));
        assertFalse(_rateLimiter.bypassRateLimit(address(this)));
    }

    function testEvaluateRateLimit() public {
        uint64 batchSize = 3;
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);
        uint256 blocks = 6;
        uint256 txs = 3;
        uint256 expectedBatches = blocks / batchSize;
        _rateLimiter.setRateLimitParams(RateLimitParams({duration: 10, maxAmount: MILLION_USDC, batchSize: batchSize}));

        bool result;
        for (uint256 i = 0; i < blocks; i++) {
            vm.roll(i);
            for (uint256 j = 0; j < txs; j++) {
                result = _rateLimiter.evaluateRateLimit(_token, 1e18);
            }
        }
        TxHistory memory txHistory = _rateLimiter.getTxHistory(address(this));
        uint256 expectedTotal = _scaleNumber(txs * blocks * currentPrice);
        assertEq(txHistory.total, expectedTotal);
        assertEq(txHistory.txBatches.length, expectedBatches);
        assertEq(txHistory.ptr, 0);

        _rateLimiter.setRateLimitParams(RateLimitParams({duration: 1, maxAmount: MILLION_USDC, batchSize: 1}));
        vm.roll(blocks + 1);
        result = _rateLimiter.evaluateRateLimit(_token, 1e18);
        txHistory = _rateLimiter.getTxHistory(address(this));
        expectedTotal = _scaleNumber(currentPrice);
        assertEq(txHistory.total, expectedTotal);
        assertEq(txHistory.ptr, txHistory.txBatches.length - 1);
    }

    function testEvaluateRateLimitExpiredTxs() public {
        uint256 duration = 5;
        uint256 blocks = 3;
        _rateLimiter.setRateLimitParams(RateLimitParams({duration: duration, maxAmount: MILLION_USDC, batchSize: 1}));
        for (uint256 i = 0; i < blocks; i++) {
            vm.roll(i);
            _rateLimiter.evaluateRateLimit(_token, 1e18);
        }
        vm.roll(duration * 5);
        _rateLimiter.evaluateRateLimit(_token, 1e18);
        TxHistory memory txHistory = _rateLimiter.getTxHistory(address(this));
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100e18);
        uint256 expectedTotal = _scaleNumber(currentPrice);
        assertEq(txHistory.total, expectedTotal);
    }

    function testEvaluateRateLimitBigBatch() public {
        uint256 blocks = 10;
        uint256 txs = 3;
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);
        _rateLimiter.setRateLimitParams(RateLimitParams({duration: 10, maxAmount: MILLION_USDC, batchSize: 100}));
        for (uint256 i = 0; i < blocks; i++) {
            vm.roll(i);
            for (uint256 j = 0; j < txs; j++) {
                _rateLimiter.evaluateRateLimit(_token, 1e18);
            }
        }
        TxHistory memory txHistory = _rateLimiter.getTxHistory(address(this));
        uint256 expectedTotal = _scaleNumber(txs * blocks * currentPrice);
        assertEq(txHistory.total, expectedTotal);
    }

    function testEvaluateRateLimitWithBatchContainingExpiredBlocks() public {
        uint64 batchSize = 3;
        uint256 duration = 5;
        uint256 blocks = 3 * batchSize;
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100e18);
        _rateLimiter.setRateLimitParams(
            RateLimitParams({duration: duration, maxAmount: MILLION_USDC, batchSize: batchSize})
        );
        for (uint256 i = 0; i < blocks; i++) {
            vm.roll(i);
            _rateLimiter.evaluateRateLimit(_token, 1e18);
        }
        TxHistory memory txHistory = _rateLimiter.getTxHistory(address(this));
        uint256 expectedPtr = (blocks / batchSize) - (duration % batchSize);
        uint256 remainingBatches = txHistory.txBatches.length - expectedPtr;
        uint256 expectedTotal = _scaleNumber(remainingBatches * batchSize * currentPrice);
        assertEq(txHistory.ptr, expectedPtr);
        assertEq(txHistory.total, expectedTotal);
    }

    // right now this needs to run last because it will rate limit the other
    // write-path tests such as insertTx
    // TODO: fix that
    function testCheckIfLimitExceeds() public {
        RateLimitParams memory rateLimitParams = _rateLimiter.getRateLimitParams();
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);
        uint256 amount = 1e18;
        (bool exceedsLimit,) = _rateLimiter.checkIfLimitExceeds(msg.sender, _token, amount);
        assertEq(exceedsLimit, false);
        uint256 largeAmount = ((rateLimitParams.maxAmount / currentPrice) + 1) * 1e18;
        (exceedsLimit,) = _rateLimiter.checkIfLimitExceeds(msg.sender, _token, largeAmount);
        assertEq(exceedsLimit, true);
    }

    function testCheckIfLimitExceedsWithTxn() public {
        address testSender = makeAddr("testSender");
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);
        uint256 amount = 1e18;

        vm.prank(testSender);
        _rateLimiter.evaluateRateLimit(_token, amount);

        (bool exceedsLimit, uint256 remainingAmount) = _rateLimiter.checkIfLimitExceeds(testSender, _token, amount);
        assertEq(exceedsLimit, false);
        uint256 expectedRemainingAmount = _scaleNumber(1_000_000e6 - 2 * currentPrice);
        assertEq(remainingAmount, expectedRemainingAmount);
    }

    function testCheckIfLimitExceedsWithThreeTxns() public {
        address testSender = makeAddr("testSender");
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);
        uint256 amount = 1e18;

        vm.prank(testSender);
        _rateLimiter.evaluateRateLimit(_token, amount);

        vm.prank(testSender);
        _rateLimiter.evaluateRateLimit(_token, amount);

        (bool exceedsLimit, uint256 remainingAmount) = _rateLimiter.checkIfLimitExceeds(testSender, _token, amount);
        assertEq(exceedsLimit, false);
        uint256 expectedRemainingAmount = _scaleNumber(1_000_000e6 - 3 * currentPrice);
        assertEq(remainingAmount, expectedRemainingAmount);
    }

    function testCheckIfLimitExceedsWithRemainingAmount() public {
        address testSender = makeAddr("testSender");
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);
        uint256 amount = (_rateLimiter.getRateLimitParams().maxAmount / currentPrice) * 1e18;

        vm.prank(testSender);
        _rateLimiter.evaluateRateLimit(_token, amount);

        (bool exceedsLimit, uint256 remainingAmount) = _rateLimiter.checkIfLimitExceeds(testSender, _token, amount);
        assertEq(exceedsLimit, true);
    }

    function testCheckIfLimitExceedsUnsupportedToken() public {
        vm.expectRevert();
        _rateLimiter.checkIfLimitExceeds(msg.sender, address(69), 2);
    }

    function testFuzz_SetRateLimitParams(uint256 duration, uint256 maxAmount, uint64 batchSize) public {
        duration = bound(duration, 1, 1000);
        maxAmount = bound(maxAmount, 1e6, 1e12);
        batchSize = uint64(bound(batchSize, 1, 100));

        RateLimitParams memory newParams =
            RateLimitParams({duration: duration, maxAmount: maxAmount, batchSize: batchSize});
        _setRateLimitParams(newParams);

        RateLimitParams memory fetchedParams = _rateLimiter.getRateLimitParams();
        assertEq(fetchedParams.duration, duration);
        assertEq(fetchedParams.maxAmount, maxAmount);
        assertEq(fetchedParams.batchSize, batchSize);
    }

    function testFuzz_EvaluateRateLimit(
        uint256 amount
    ) public {
        amount = bound(amount, 1, 1e20);

        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);
        uint256 usdValue = (amount * currentPrice) / 1e18;

        bool result = _rateLimiter.evaluateRateLimit(_token, amount);

        if (usdValue <= MILLION_USDC) {
            assertTrue(result, "Rate limit should not be exceeded");
        } else {
            assertFalse(result, "Rate limit should be exceeded");
        }
    }

    function testFuzz_CheckIfLimitExceeds(address sender, uint256 amount) public {
        amount = bound(amount, 1, 1e20);

        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);
        uint256 usdValue = (amount * currentPrice) / 1e18;

        (bool exceedsLimit, uint256 remainingAmount) = _rateLimiter.checkIfLimitExceeds(sender, _token, amount);

        if (usdValue <= MILLION_USDC) {
            assertFalse(exceedsLimit, "Limit should not be exceeded");
            assertGe(remainingAmount, 0, "Remaining amount should be non-negative");
        } else {
            assertTrue(exceedsLimit, "Limit should be exceeded");
            assertEq(remainingAmount, 0, "Remaining amount should be zero when limit is exceeded");
        }
    }

    function testFuzz_MultipleTxsOverTime(uint8 txCount, uint256 initialAmount, uint8 blocksBetweenTx) public {
        txCount = uint8(bound(txCount, 1, 50));
        initialAmount = bound(initialAmount, 1e15, 1e18);
        blocksBetweenTx = uint8(bound(blocksBetweenTx, 1, 10));

        uint256 totalUsdValue = 0;
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);

        for (uint8 i = 0; i < txCount; i++) {
            uint256 amount = initialAmount + (i * 1e15);
            uint256 usdValue = (amount * currentPrice) / 1e18;
            totalUsdValue += usdValue;

            bool result = _rateLimiter.evaluateRateLimit(_token, amount);

            if (totalUsdValue <= MILLION_USDC) {
                assertTrue(result, "Rate limit should not be exceeded");
            } else {
                assertFalse(result, "Rate limit should be exceeded");
                break;
            }

            vm.roll(block.number + blocksBetweenTx);
        }

        TxHistory memory txHistory = _rateLimiter.getTxHistory(address(this));
        assertLe(txHistory.total, _scaleNumber(MILLION_USDC), "Total USD value should not exceed the rate limit");
    }

    function testFuzz_PriceFluctuationOverTime(uint8 txCount, uint256 initialPrice, uint256 initialAmount) public {
        txCount = uint8(bound(txCount, 1, 50));
        initialPrice = bound(initialPrice, 1e6, 100e6); // 1 USD to 100 USD
        initialAmount = bound(initialAmount, 1e15, 1e18);

        for (uint8 i = 0; i < txCount; i++) {
            uint256 newPrice = initialPrice + (i * 1e5);
            uint256 amount = initialAmount + (i * 1e15);

            _mockPriceAggregator.setPrice(_token, newPrice);

            uint256 usdValue = (amount * newPrice) / 1e18;

            bool result = _rateLimiter.evaluateRateLimit(_token, amount);

            if (usdValue <= MILLION_USDC) {
                assertTrue(result, "Rate limit should not be exceeded");
            } else {
                assertFalse(result, "Rate limit should be exceeded");
                break;
            }

            vm.roll(block.number + 1);
        }
    }

    function testFuzz_DurationExpiryAndReset(uint256 numTxs, uint256 amount) public {
        numTxs = bound(numTxs, 1, 50);
        amount = bound(amount, 1, 1e18);

        address testSender = makeAddr("testSender");
        uint256 currentPrice = _mockPriceAggregator.getPrice(_token, 100);
        uint256 usdValue = amount * currentPrice / 1e18;

        uint256 duration = 5;
        _rateLimiter.setRateLimitParams(RateLimitParams({duration: duration, maxAmount: MILLION_USDC, batchSize: 1}));

        for (uint256 i = 0; i < numTxs; i++) {
            vm.prank(testSender);
            bool result = _rateLimiter.evaluateRateLimit(_token, amount);

            if ((i + 1) * usdValue <= MILLION_USDC) {
                assertTrue(result, "Rate limit should not be exceeded within duration");
            } else {
                assertFalse(result, "Rate limit should be exceeded within duration");
            }

            vm.roll(block.number + 1);
        }

        vm.roll(block.number + duration + 1);

        vm.prank(testSender);
        bool resetResult = _rateLimiter.evaluateRateLimit(_token, MILLION_USDC - 1);
        assertTrue(resetResult, "Rate limit should be reset after duration expiry");
    }

    function _scaleNumber(
        uint256 result
    ) private view returns (uint256) {
        return result.mulDivDown(USDC_SCALING_FACTOR, USDC_PRECISION);
    }
}
