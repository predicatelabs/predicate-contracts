// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {IPriceAggregator} from "../../src/interfaces/IPriceAggregator.sol";

contract MockPriceAggregator is IPriceAggregator {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token, uint256 amountIn) external view override returns (uint256) {
        require(prices[token] != 0, "MockPriceAggregator: token not supported");
        require(amountIn > 0, "MockPriceAggregator: amountIn must be greater than 0");
        return prices[token];
    }

    function assetToAsset(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 twapPeriod
    ) external pure override returns (uint256 amountOut) {
        (tokenIn, amountIn, tokenOut, twapPeriod);
        return 0;
    }

    function isTokenSupported(
        address token
    ) external view override returns (bool) {
        return prices[token] != 0;
    }
}
