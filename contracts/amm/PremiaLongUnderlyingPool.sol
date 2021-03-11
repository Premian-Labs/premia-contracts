// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './PremiaLiquidityPool.sol';

contract PremiaLongUnderlyingPool is PremiaLiquidityPool {
  constructor(address _controller) PremiaLiquidityPool(_controller) {}

  function writeOptionFor(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) public override {
    super.writeOptionFor(_receiver, _optionContract, _optionId, _amount, _premiumToken, _amountPremium, _referrer);

    // TODO: 
    // 1. Take loan from short pools
    // 2. Buy underlying token with loan token on dex to long it
  }

  function unwindOptionFor(address _sender, address _optionContract, uint256 _optionId, uint256 _amount) public override {
    super.unwindOptionFor(_sender, _optionContract, _optionId, _amount);

    // TODO: 
    // 1. Sell underlying token bought earlier
    // 2. Repay loan to short pool
  }

  function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) public override {
    super.unlockCollateralFromOption(_optionContract, _optionId, _amount);

    // TODO: 
    // 1. Sell underlying token bought earlier
    // 2. Repay loan to short pool
  }
}