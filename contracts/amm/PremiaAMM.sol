// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';

contract PremiaAMM is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // The oracle used to get black scholes prices on chain.
  IBlackScholesPriceGetter public blackScholesOracle;

  IPremiaLiquidityPool[] public callPools;
  IPremiaLiquidityPool[] public putPools;

  uint256 k = 1;

  function getCallReserves(address optionContract, uint256 optionId) public view returns (uint256 reserveAmount) {
    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);
    return _getCallReserves(data);
  }

  function _getCallReserves(IPremiaOption.OptionData memory data) internal view returns (uint256 reserveAmount) {
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      reserveAmount = reserveAmount.add(pool.getWritableAmount(data.token, data.expiration));
    }

    return reserveAmount;
  }

  function getPutReserves(address optionContract, uint256 optionId) public view returns (uint256 reserveAmount) {
    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);
    return _getPutReserves(data, IPremiaOption(optionContract));
  }

  function _getPutReserves(IPremiaOption.OptionData memory data, IPremiaOption optionContract) internal view returns (uint256 reserveAmount) {
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      reserveAmount = reserveAmount.add(pool.getWritableAmount(optionContract.denominator(), data.expiration));
    }

    return reserveAmount;
  }

  function getCallMaxBuy(address optionContract, uint256 optionId) public view returns (uint256 maxBuy) {
    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);
    return _getCallMaxBuy(data);
  }

  function _getCallMaxBuy(IPremiaOption.OptionData memory data) internal view returns (uint256 maxBuy) {
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      uint256 reserves = pool.getWritableAmount(data.token, data.expiration);

      if (reserves > maxBuy) {
        maxBuy = reserves; 
      }
    }

    return maxBuy;
  }

  function getCallMaxSell(address optionContract, uint256 optionId) public view returns (uint256 maxSell) {
    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);
    return _getCallMaxSell(optionId);
  }

  function _getCallMaxSell(uint256 optionId) internal view returns (uint256 maxSell) {
    // TODO: calculate max sell
    return maxSell;
  }

  function getPutMaxBuy(address optionContract, uint256 optionId) public view returns (uint256 maxBuy) {
    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);
    return _getPutMaxBuy(data, IPremiaOption(optionContract), optionId);
  }

  function _getPutMaxBuy(IPremiaOption.OptionData memory data, IPremiaOption optionContract, uint256 optionId) internal view returns (uint256 maxBuy) {
    for (uint256 i = 0; i < putPools.length; i++) {
      IPremiaLiquidityPool pool = putPools[i];
      uint256 reserves = pool.getWritableAmount(optionContract.denominator(), data.expiration);

      if (reserves > maxBuy) {
        maxBuy = reserves; 
      }
    }

    return maxBuy;
  }

  function getPutMaxSell(address optionContract, uint256 optionId) public view returns (uint256 maxSell) {
    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);
    return _getPutMaxSell(data, IPremiaOption(optionContract), optionId);
  }

  function _getPutMaxSell(IPremiaOption.OptionData memory data, IPremiaOption optionContract, uint256 optionId) internal view returns (uint256 maxSell) {
    // TODO: calculate max sell
    return maxSell;
  }

  function priceOption(IPremiaOption.OptionData memory data, IPremiaOption optionContract, uint256 optionId, uint256 amount, address premiumToken)
    public view returns (uint256 optionPrice) {
    // Source: https://arxiv.org/pdf/2101.02778.pdf (page 5)
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

    uint256 x_t_0;
    uint256 x_t_1;
    uint256 y_t_0;
    uint256 y_t_1;
    uint256 k_0 = k;

    if (data.isCall) {
      x_t_0 = _getCallReserves(data);
      x_t_1 = x_t_0.sub(amount);
      y_t_0 = _getPutReserves(data, optionContract);
      y_t_1 = y_t_0;
    } else {
      x_t_0 = _getCallReserves(data);
      x_t_1 = x_t_0;
      y_t_0 = _getPutReserves(data, optionContract);
      y_t_1 = y_t_0.sub(amount.mul(data.strikePrice));
    }

    uint256 p_market_t = blackScholesOracle.getBlackScholesEstimate(address(optionContract), optionId);

    uint256 a_t_0 = x_t_0.sub(y_t_0.div(p_market_t));
    uint256 w_t_0 = k_0.mul(p_market_t).div(y_t_0.mul(y_t_0));
    uint256 k_1 = w_t_0.mul(x_t_0.sub(a_t_0)).mul(y_t_0);

    uint256 a_t_1 = x_t_1.sub(y_t_1.div(p_market_t));
    uint256 w_t_1 = k_1.mul(p_market_t).div(y_t_1.mul(y_t_1));

    uint256 x_t_1_diff = x_t_1.sub(a_t_1);

    return k_1.div(w_t_1).mul(uint256(1e12).div(x_t_1_diff.mul(x_t_1_diff))).div(1e12);
  }

  function _priceOptionWithUpdate(IPremiaOption.OptionData memory data, IPremiaOption optionContract, uint256 optionId, uint256 amount, address premiumToken)
    internal returns (uint256 optionPrice) {
    uint256 x_t;
    uint256 y_t;

    if (data.isCall) {
      x_t = _getCallReserves(data).sub(amount);
      y_t = _getPutReserves(data, optionContract);
    } else {
      x_t = _getCallReserves(data);
      y_t = _getPutReserves(data, optionContract).sub(amount.mul(data.strikePrice));
    }

    _updateKFromReserves(data, optionContract, optionId, amount, premiumToken);

    uint256 p_market_t = blackScholesOracle.getBlackScholesEstimate(address(optionContract), optionId);
    uint256 a_t = x_t.sub(y_t.div(p_market_t));
    uint256 w_t = k.mul(p_market_t).div(y_t.mul(y_t));

    uint256 x_t_diff = x_t.sub(a_t);

    return k.div(w_t).mul(uint256(1e12).div(x_t_diff.mul(x_t_diff))).div(1e12);
  }

  function _updateKFromReserves(IPremiaOption.OptionData memory data, IPremiaOption optionContract, uint256 optionId, uint256 amount, address premiumToken) internal {
    uint256 p_market_t = blackScholesOracle.getBlackScholesEstimate(address(optionContract), optionId);
    uint256 x_t = _getCallReserves(data);
    uint256 y_t = _getPutReserves(data, optionContract);
    uint256 a_t = x_t.sub(y_t.div(p_market_t));
    uint256 w_t = k.mul(p_market_t).div(y_t.mul(y_t));

    k = w_t.mul(x_t.sub(a_t)).mul(y_t);
  }

  function _getLiquidityPool(IPremiaOption.OptionData memory data, IPremiaOption optionContract, uint256 amount) internal returns (IPremiaLiquidityPool) {
    IPremiaLiquidityPool[] memory liquidityPools = data.isCall ? callPools : putPools;

    for (uint256 i = 0; i < liquidityPools.length; i++) {
      IPremiaLiquidityPool pool = liquidityPools[i];
      uint256 amountAvailable = pool.getWritableAmount(data.isCall ? data.token : optionContract.denominator(), data.expiration);

      if (amountAvailable >= amount) {
        return pool;
      }
    }

    revert("Not enough liquidity");
  }

  function buy(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 maxPremiumAmount, address referrer) external {
    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);
    IPremiaLiquidityPool liquidityPool = _getLiquidityPool(data, IPremiaOption(optionContract), amount);

    uint256 optionPrice = _priceOptionWithUpdate(data, IPremiaOption(optionContract), optionId, amount, premiumToken);

    require(optionPrice >= maxPremiumAmount, "Price too high.");

    IERC20(premiumToken).safeTransferFrom(msg.sender, address(liquidityPool), optionPrice);
    liquidityPool.writeOptionFor(msg.sender, optionContract, optionId, amount, premiumToken, optionPrice, referrer);
  }

  function sell(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 minPremiumAmount, address referrer) external {
    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);
    IPremiaLiquidityPool liquidityPool = _getLiquidityPool(data, IPremiaOption(optionContract), amount);

    uint256 optionPrice = _priceOptionWithUpdate(data, IPremiaOption(optionContract), optionId, amount, premiumToken);

    require(optionPrice <= minPremiumAmount, "Price too low.");

    liquidityPool.unwindOptionFor(msg.sender, optionContract, optionId, amount, premiumToken, optionPrice);
    IERC20(premiumToken).safeTransferFrom(address(liquidityPool), msg.sender, optionPrice);
  }
}