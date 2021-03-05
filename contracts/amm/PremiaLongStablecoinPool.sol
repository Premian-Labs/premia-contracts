// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import './PremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IPremiaAMM.sol';

contract PremiaLongStablecoinPool is PremiaLiquidityPool {
  IPremiaAMM amm;

  function getLoanableAmount(address _token, uint256 _lockExpiration) public override returns (uint256) {
    return 0;
  }

  function writeOptionFor(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) public override {
    super.writeOptionFor(_receiver, _optionContract, _optionId, _amount, _premiumToken, _amountPremium, _referrer);
    amm.buy(_optionContract, _optionId, _amount, _premiumToken, _amountPremium, _referrer);
  }

  function unwindOptionFor(address _sender, address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium) public override {
    super.unwindOptionFor(_sender, _optionContract, _optionId, _amount, _premiumToken, _amountPremium);
    amm.sell(_optionContract, _optionId, _amount, _premiumToken, _amountPremium, _sender);
  }

  function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) public override {
    super.unlockCollateralFromOption(_optionContract, _optionId, _amount);
    amm.sell(_optionContract, _optionId, _amount, IPremiaOption(_optionContract).denominator(), 0, msg.sender);
  }
}