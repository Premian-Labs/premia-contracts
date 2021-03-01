// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';

contract PremiaAMM is Ownable {
  using SafeMath for uint256;

  // The oracle used to get black scholes prices on chain.
  IBlackScholesPriceGetter public blackScholesOracle;

  IPremiaLiquidityPool[] public callPools;
  IPremiaLiquidityPool[] public putPools;

  uint256 k;

  function getCallReserves(address optionContract, uint256 optionId) public view returns (uint256 reserveAmount);
  function _getCallReserves(uint256 optionId) internal returns (uint256 reserveAmount);
  function getPutReserves(address optionContract, uint256 optionId) public view returns (uint256 reserveAmount);
  function _getPutReserves(IPremiaOption.OptionData data, IPremiaOption optionContract, uint256 optionId) internal returns (uint256 reserveAmount);
  function getCallMaxBuy(address optionContract, uint256 optionId) public view returns (uint256 maxBuy);
  function _getCallMaxBuy(uint256 optionId) internal returns (uint256 maxBuy);
  function getCallMaxSell(address optionContract, uint256 optionId) public view returns (uint256 maxSell);
  function getPutMaxBuy(address optionContract, uint256 optionId) public view returns (uint256 maxBuy);
  function _getPutMaxBuy(IPremiaOption.OptionData data, IPremiaOption optionContract, uint256 optionId) internal returns (uint256 maxBuy);
  function getPutMaxSell(address optionContract, uint256 optionId) public view returns (uint256 maxSell);
  function _getPutMaxSell(IPremiaOption.OptionData data, IPremiaOption optionContract, uint256 optionId) internal returns (uint256 maxSell);
  function priceOption(IPremiaOption.OptionData data, IPremiaOption optionContract, uint256 optionId, uint256 amount, address premiumToken)
    public view returns (uint256 optionPrice);
  function _priceOptionWithUpdate(IPremiaOption.OptionData data, IPremiaOption optionContract, uint256 optionId, uint256 amount, address premiumToken)
    internal returns (uint256 optionPrice);
  function _updateKFromReserves(IPremiaOption.OptionData data, IPremiaOption optionContract, uint256 optionId, uint256 amount, address premiumToken)
    internal;
  function _getLiquidityPool(IPremiaOption.OptionData data, IPremiaOption optionContract, uint256 optionId, uint256 amount)
    internal returns (IPremiaLiquidityPool);
  function buy(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 maxPremiumAmount, address referrer) external;
  function sell(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 minPremiumAmount, address referrer) external;
}