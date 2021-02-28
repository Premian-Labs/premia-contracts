// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';

contract PremiaAMM is Ownable {
  using SafeMath for uint256;

  // The oracle used to get black scholes prices on chain.
  IBlackScholesPriceGetter public blackScholesOracle;

  IPremiaLiquidityPool public callPool;
  IPremiaLiquidityPool public putPool;

  uint256 k = 1;

  function priceOption(IPremiaOption optionContract, uint256 optionId, uint256 amount, address premiumToken) public returns (uint256 optionPrice) {
    // sum all call reserves + put reserves and plug into the following formula:
    // k = w(t) · (x(t) − a(t)) · y(t)
    // a(t) < x(t), w(t) > 0, x(t) > 0, y(t) > 0
    // where w(t) and a(t) are both functions of the current price,
    // x(t) is the amount of reserves in the call pool
    // y(t) is the amount of reserves in the put pool
    // and k is a constant set at initialization of the pool

    // instantaneous price at any moment can be found through the following:
    // optionPrice = (k / w(t)) *  (1 / (x(t) - a(t))^2 
    // where a(t) = x(t) − (y(t) / p_market(t))
    // and w(t) = (k * p_market(t)) / y(t)^2
    //
    // Source: https://arxiv.org/pdf/2101.02778.pdf (page 5)

    IPremiaOption.OptionData data = optionContract.optionData(optionId);

    uint256 x_t_0;
    uint256 x_t_1;
    uint256 y_t_0;
    uint256 y_t_1;

    if (data.isCall) {
      x_t_0 = callPool.getLoanableAmount(data.token, data.expiration);
      x_t_1 = x_t_0.sub(amount);
      y_t_0 = putPool.getLoanableAmount(optionContract.denominator(), data.expiration);
      y_t_1 = y_t_0;
    } else {
      x_t_0 = callPool.getLoanableAmount(data.token, data.expiration);
      x_t_1 = x_t_0;
      y_t_0 = putPool.getLoanableAmount(optionContract.denominator(), data.expiration);
      y_t_1 = y_t_0.sub(amount.mul(data.strikePrice));
    }
    uint256 a_t_0 = x_t_0.sub(y_t_0.div(p_market_t));
    uint256 w_t_0 = k.mul(p_market_t).div(y_t_0.pow(2));

    k = w_t_0.mul(x_t_0.sub(a_t_0)).mul(y_t_0);

    uint256 p_market_t = blackScholesOracle.getBlackScholesEstimate(address(optionContract), optionId);
    uint256 a_t_1 = x_t_1.sub(y_t_1.div(p_market_t));
    uint256 w_t_1 = k.mul(p_market_t).div(y_t_1.pow(2));

    uint256 optionPrice = k.div(w_t_1).mul(1.div((x_t_1.sub(a_t_1)).pow(2)));
  }

  function buy(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 maxPremiumAmount, address referrer) external {
    uint256 optionPrice = priceOption(optionContract, optionId, amount, premiumToken);

    require(optionPrice >= maxPremiumAmount, "Price too high.");

    IPremiaOption.OptionData data = optionContract.optionData(optionId);
    IPremiaLiquidityPool liquidityPool = isCall ? callPool : putPool;

    IERC20(premiumToken).safeTransferFrom(msg.sender, liquidityPool, optionPrice);
    liquidityPool.writeOptionFor(msg.sender, optionContract, optionId, amount, premiumToken, optionPrice, referrer);
  }

  function sell(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 minPremiumAmount, address referrer) external {
    uint256 optionPrice = priceOption(optionContract, optionId, amount, premiumToken);

    require(optionPrice <= minPremiumAmount, "Price too low.");

    IPremiaOption.OptionData data = optionContract.optionData(optionId);
    IPremiaLiquidityPool liquidityPool = isCall ? callPool : putPool;

    liquidityPool.unwindOptionFor(msg.sender, optionContract, optionId, amount, premiumToken, optionPrice, referrer);
    IERC20(premiumToken).safeTransferFrom(liquidityPool, msg.sender, optionPrice);
  }
}