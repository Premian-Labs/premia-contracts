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

    function getBlackScholesEstimateFromOptionId(IPremiaOption _optionContract, uint256 _optionId, uint256 _amountIn) external view returns (uint256) {
        IPremiaOption.OptionData memory data = _optionContract.optionData(_optionId);
        return getBlackScholesEstimate(data.token, _optionContract.denominator(), data.strikePrice, data.expiration, _amountIn);
    }

    function getBlackScholesEstimate(address _token, address _denominator, uint256 _strikePrice, uint256 _expiration, uint256 _amountIn) public view returns (uint256) {
        uint256 vol = blackScholesOracle.realizedVolatilityWeekly(_token, _amountIn, _denominator);
        uint256 price = priceOracle.getAssetPrice(_token);

        uint256 time = _expiration - block.timestamp;
        uint256 basePrice = blackScholesOracle.blackScholesEstimate(vol, price, time);

        if (price > _strikePrice) {
          return basePrice + _amountIn * (price - _strikePrice);
        }

        return basePrice - _amountIn * (_strikePrice - price);
    }

    function getAssetPrice(address _asset) external view returns (uint256) {
        return priceOracle.getAssetPrice(_asset);
    }
}