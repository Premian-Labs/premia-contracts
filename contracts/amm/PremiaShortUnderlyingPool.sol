// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import './PremiaLiquidityPool.sol';

contract PremiaShortUnderlyingPool is PremiaLiquidityPool {
  function writeOptionFor(address receiver, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium, address referrer) external {
    super.writeOptionFor(receiver, optionContract, optionId, amount, premiumToken, amountPremium, referrer);

    // TODO: 
    // 1. Take loan from call pools
    // 2. Sell loaned token on dex to short it
  }

  function unwindOptionFor(address sender, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium) external {
    super.unwindOptionFor(receiver, optionContract, optionId, amount, premiumToken, amountPremium);

    // TODO: 
    // 1. Sell loaned token bought earlier
    // 2. Repay loan from call pool
  }

  function unlockCollateralFromOption(address optionContract, uint256 optionId, uint256 amount) external {
    super.unlockCollateralFromOption(optionContract, optionId, amount);

    // TODO: 
    // 1. Sell loaned token bought earlier
    // 2. Repay loan from call pool
  }
}