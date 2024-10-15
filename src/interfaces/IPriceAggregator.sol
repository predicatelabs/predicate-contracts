// SPDX-License-Identifier: MIT

pragma solidity =0.8.12;

interface IPriceAggregator {
    /**
     * @notice Given a token, return the price of the token
     * @param token Address of the token
     * @param amountIn Amount of token to be converted
     * @return price of the token in USDC
     */
    function getPrice(address token, uint256 amountIn) external view returns (uint256);

    /**
     * @notice Given a token and its amount, return the equivalent value in another token
     * @param tokenIn Address of an ERC20 token contract to be converted
     * @param amountIn Amount of tokenIn to be converted
     *  @param tokenOut Address of an ERC20 token contract to convert into
     * @param twapPeriod Number of seconds in the past to consider for the TWAP rate, if applicable
     * @return amountOut Amount of tokenOut received for amountIn of tokenIn
     */
    function assetToAsset(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 twapPeriod
    ) external view returns (uint256 amountOut);

    /**
     * @notice is token supported
     * @param token Address of the token
     * @return true if token is supported
     */
    function isTokenSupported(
        address token
    ) external view returns (bool);
}
