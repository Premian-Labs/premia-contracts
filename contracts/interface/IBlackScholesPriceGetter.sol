// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IPremiaOption.sol";
import "./IPriceOracleGetter.sol";
import '../interface/IPremiaOption.sol';

/**
 * @title IBlackScholesPriceGetter interface
 * @notice Interface for the Premia black scholes price oracle.
 */
interface IBlackScholesPriceGetter is IPriceOracleGetter {
    function getBlackScholesEstimateFromOptionId(IPremiaOption _optionContract, uint256 _optionId, uint256 amountIn) external view returns (uint256);
    function getBlackScholesEstimate(address _token, address _denominator, uint256 _strikePrice, uint256 _expiration, uint256 _amountIn) external view returns (uint256);

    /**
     * @dev returns the asset price in ETH
     */
    function getAssetPrice(address _asset) override external view returns (uint256);
}