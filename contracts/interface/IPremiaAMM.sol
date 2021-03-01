// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';

interface IPremiaAMM {
  function getCallReserves(address optionContract, uint256 optionId) external view returns (uint256 reserveAmount);
  function getPutReserves(address optionContract, uint256 optionId) external view returns (uint256 reserveAmount);
  function getCallMaxBuy(address optionContract, uint256 optionId) external view returns (uint256 maxBuy);
  function getCallMaxSell(address optionContract, uint256 optionId) external view returns (uint256 maxSell);
  function getPutMaxBuy(address optionContract, uint256 optionId) external view returns (uint256 maxBuy);
  function getPutMaxSell(address optionContract, uint256 optionId) external view returns (uint256 maxSell);
  function priceOption(IPremiaOption.OptionData memory data, IPremiaOption optionContract, uint256 optionId, uint256 amount, address premiumToken)
  external view returns (uint256 optionPrice);
  function buy(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 maxPremiumAmount, address referrer) external;
  function sell(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 minPremiumAmount, address referrer) external;
}