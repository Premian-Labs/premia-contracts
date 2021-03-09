// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '../interface/IPriceOracleGetter.sol';
import '../interface/ISushiswapV1Oracle.sol';
import '../interface/IPremiaOption.sol';

contract PremiaBlackScholesV1Oracle {
    ISushiswapV1Oracle public blackScholesOracle;
    IPriceOracleGetter public priceOracle;

    constructor(ISushiswapV1Oracle _blackScholesOracle, IPriceOracleGetter _priceOracle) {
        blackScholesOracle = _blackScholesOracle;
        priceOracle = _priceOracle;
    }

    /**
     * @dev returns the black scholes price in ETH
     */
    function getBlackScholesEstimate(IPremiaOption optionContract, uint256 optionId, uint256 amountIn) external view returns (uint256) {
        uint256 vol = blackScholesOracle.realizedVolatilityWeekly(optionContract.token, amountIn, optionContract.denominator);
        uint256 price = priceOracle.getAssetPrice(optionContract.token);

        IPremiaOption.OptionData memory data = optionContract.optionData(optionId);

        uint256 time = data.expiration - block.timestamp;
        uint256 basePrice = blackScholesOracle.blackScholesEstimate(vol, price, time);

        if (price > data.strikePrice) {
          return basePrice + amountIn * (price - data.strikePrice);
        }

        return basePrice - amountIn * (data.strikePrice - price);
    }
}