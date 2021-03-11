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

    function getBlackScholesEstimate(IPremiaOption _optionContract, uint256 _optionId, uint256 _amountIn) external view returns (uint256) {
        IPremiaOption.OptionData memory data = _optionContract.optionData(_optionId);

        uint256 vol = blackScholesOracle.realizedVolatilityWeekly(data.token, _amountIn, _optionContract.denominator());
        uint256 price = priceOracle.getAssetPrice(data.token);

        uint256 time = data.expiration - block.timestamp;
        uint256 basePrice = blackScholesOracle.blackScholesEstimate(vol, price, time);

        if (price > data.strikePrice) {
          return basePrice + _amountIn * (price - data.strikePrice);
        }

        return basePrice - _amountIn * (data.strikePrice - price);
    }
}