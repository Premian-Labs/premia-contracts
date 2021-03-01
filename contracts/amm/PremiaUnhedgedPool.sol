// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import './PremiaLiquidityPool.sol';

contract PremiaUnhedgedPool is PremiaLiquidityPool {
  function getLoanableAmount(address token, uint256 lockExpiration) public returns (uint256 loanableAmount) {
    loanableAmount = 0;
  }

  function borrow(address token, uint256 amountToken, address collateralToken, uint256 amountCollateral, uint256 lockExpiration) external {
    revert;
  }

  function repay(bytes32 hash, uint256 amount) public {
    revert;
  }

  function liquidate(bytes32 hash, uint256 collateralAmount, address router) public {
    revert;
  }
}