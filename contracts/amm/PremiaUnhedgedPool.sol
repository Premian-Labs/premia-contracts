// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';

import './PremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IPriceOracleGetter.sol';
import '../uniswapV2/interfaces/IUniswapV2Router02.sol';

contract PremiaNeutralPool is PremiaLiquidityPool {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

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