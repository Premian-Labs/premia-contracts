// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';

interface IPremiaAMM {
  function getCallReserves(address _optionContract, uint256 _optionId) external view returns (uint256);
  function getPutReserves(address _optionContract, uint256 _optionId) external view returns (uint256);
  function getCallMaxBuy(address _optionContract, uint256 _optionId) external view returns (uint256);
  function getCallMaxSell(address _optionContract, uint256 _optionId) external view returns (uint256);
  function getPutMaxBuy(address _optionContract, uint256 _optionId) external view returns (uint256);
  function getPutMaxSell(address _optionContract, uint256 _optionId) external view returns (uint256);
  function priceOption(IPremiaOption.OptionData memory _data, IPremiaOption _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken) external view returns (uint256);
  function buy(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _maxPremiumAmount, address _referrer) external;
  function sell(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _minPremiumAmount, address _referrer) external;
}