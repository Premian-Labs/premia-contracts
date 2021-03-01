// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import './PremiaLiquidityPool.sol';

contract PremiaLongUnderlyingPool is PremiaLiquidityPool {
  function writeOptionFor(address receiver, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium, address referrer) public override {
    super.writeOptionFor(receiver, optionContract, optionId, amount, premiumToken, amountPremium, referrer);

    // TODO: 
    // 1. Take loan from short pools
    // 2. Buy underlying token with loan token on dex to long it
  }

  function unwindOptionFor(address sender, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium) public override {
    super.unwindOptionFor(sender, optionContract, optionId, amount, premiumToken, amountPremium);

    // TODO: 
    // 1. Sell underlying token bought earlier
    // 2. Repay loan to short pool
  }

  function unlockCollateralFromOption(address optionContract, uint256 optionId, uint256 amount) public override {
    super.unlockCollateralFromOption(optionContract, optionId, amount);

    // TODO: 
    // 1. Sell underlying token bought earlier
    // 2. Repay loan to short pool
  }
}