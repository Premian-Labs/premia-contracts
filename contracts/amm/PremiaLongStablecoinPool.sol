// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import './PremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IPremiaAMM.sol';

contract PremiaLongStablecoinPool is PremiaLiquidityPool {
  IPremiaAMM amm;

  function getLoanableAmount(address token, uint256 lockExpiration) public override returns (uint256 loanableAmount) {
    return 0;
  }

  function writeOptionFor(address receiver, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium, address referrer) public override {
    super.writeOptionFor(receiver, optionContract, optionId, amount, premiumToken, amountPremium, referrer);
    amm.buy(optionContract, optionId, amount, premiumToken, amountPremium, referrer);
  }

  function unwindOptionFor(address sender, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium) public override {
    super.unwindOptionFor(sender, optionContract, optionId, amount, premiumToken, amountPremium);
    amm.sell(optionContract, optionId, amount, premiumToken, amountPremium, sender);
  }

  function unlockCollateralFromOption(address optionContract, uint256 optionId, uint256 amount) public override {
    super.unlockCollateralFromOption(optionContract, optionId, amount);
    amm.sell(optionContract, optionId, amount, IPremiaOption(optionContract).denominator(), 0, msg.sender);
  }
}