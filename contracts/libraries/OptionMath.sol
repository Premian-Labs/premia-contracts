// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ABDKMath64x64} from 'abdk-libraries-solidity/ABDKMath64x64.sol';

library OptionMath {
  using ABDKMath64x64 for int128;

  int128 internal constant ONE_64x64 = 0x10000000000000000;
  int128 internal constant THREE_64x64 = 0x30000000000000000;

  // constants used in Choudhury’s approximation of the Black-Scholes CDF
  int128 private constant CDF_CONST_0 = 0x09109f285df452394; // 2260 / 3989
  int128 private constant CDF_CONST_1 = 0x19abac0ea1da65036; // 6400 / 3989
  int128 private constant CDF_CONST_2 = 0x0d3c84b78b749bd6b; // 3300 / 3989

  /**
  * @notice TODO
  * @param today64x64 today's close
  * @param yesterday64x64 yesterday's close
  * @return log of returns
  * ln(today / yesterday)
  */
  function logreturns (
    int128 today64x64,
    int128 yesterday64x64
  ) internal pure returns (int128) {
    return today64x64.div(yesterday64x64).ln();
  }

  /**
  * @notice TODO
  * @param today64x64 today's close
  * @param yesterday64x64 yesterday's close
  * @param window the period for the EMA average
  * @return the new EMA value for today
  * alpha * (today - yesterday) + yesterday
  */
  function rollingEma (
    int128 today64x64,
    int128 yesterday64x64,
    uint256 window
  ) internal pure returns (int128) {
    return ABDKMath64x64.divu(2, window + 1).mul(
      today64x64.sub(yesterday64x64)
    ).add(yesterday64x64);
  }

  /**
  * @notice TODO
  * @param today64x64 the price from today
  * @param yesterdayEma64x64 the average from yesterday
  * @param yesterdayEmaVariance64x64 the variation from yesterday
  * @param window the period for the average
  * @return the new variance value for today
  * (1 - a)(EMAVar t-1  +  a( x t - EMA t-1)^2)
  */
  function rollingEmaVariance (
    int128 today64x64,
    int128 yesterdayEma64x64,
    int128 yesterdayEmaVariance64x64,
    uint256 window
  ) internal pure returns (int128) {
    int128 alpha = ABDKMath64x64.divu(2, window + 1);

    return ONE_64x64.sub(alpha).mul(
      yesterdayEmaVariance64x64
    ).add(
      alpha.mul(
        today64x64.sub(yesterdayEma64x64).pow(2)
      )
    );
  }

  /**
  * @notice calculate Choudhury’s approximation of the Black-Scholes CDF
  * @param x random variable
  * @return the approximated CDF of x
  */
  function N (
    int128 x
  ) internal pure returns (int128) {
    // squaring via mul is cheaper than via pow
    int128 x2 = x.mul(x);

    int128 value = (-x2 >> 1).exp().div(
      CDF_CONST_0.add(
        CDF_CONST_1.mul(x.abs())
      ).add(
        CDF_CONST_2.mul(x2.add(THREE_64x64).sqrt())
      )
    );

    return x > 0 ? ONE_64x64.sub(value) : value;
  }

  /**
  * @notice TODO
  * @param oldPoolState Pool state at t0
  * @param newPoolState Pool state at t1
  * @return return intermediate viarable Xt
  */
  function Xt (
    int128 oldPoolState,
    int128 newPoolState
  ) internal pure returns (int128) {
    return newPoolState.sub(oldPoolState).div(oldPoolState > newPoolState ? oldPoolState : newPoolState);
  }

  /**
  * @notice calculate the price of an option using the Black-Scholes model
  * @param variance TODO
  * @param strike TODO
  * @param price TODO
  * @param timeToMaturity duration of option contract (in years)
  * @param isCall whether to price "call" or "put" option
  * @return TODO
  */

  // TODO: add require to check variance, price, timeToMaturity > 0, strike => 0.5 * price,  strike <= 2 * price
  function bsPrice (
    int128 variance,
    int128 strike,
    int128 price,
    int128 timeToMaturity,
    bool isCall
  ) internal pure returns (int128) {
    int128 d1 = price.div(strike).ln().add(
      timeToMaturity.mul(variance) >> 1
    ).div(
      timeToMaturity.mul(variance).sqrt()
    );

    int128 d2 = d1.sub(timeToMaturity.mul(variance).sqrt());

    if (isCall) {
      return price.mul(N(d1)).sub(strike.mul(N(d2)));
    } else {
      return -price.mul(N(-d1)).sub(strike.mul(N(-d2)));
    }
  }

  /**
  * @notice calculate multiplier to apply to C-Level based on change in liquidity
  * @param oldPoolState liquidity in pool before update
  * @param newPoolState liquidity in pool after update
  * @param steepness steepness coefficient
  * @return new C-Level
  */
  function calculateTradingDelta (
    int128 oldPoolState,
    int128 newPoolState,
    int128 steepness
  ) internal pure returns (int128) {
    return Xt(oldPoolState, newPoolState).mul(steepness).neg().exp();
  }

  /**
  * @notice recalculate C-Level based on change in liquidity
  * @param initialCLevel C-Level of Pool before update
  * @param oldPoolState liquidity in pool before update
  * @param newPoolState liquidity in pool after update
  * @param steepness steepness coefficient
  * @return new C-Level
  */
  function calculateCLevel (
    int128 initialCLevel,
    int128 oldPoolState,
    int128 newPoolState,
    int128 steepness
  ) internal pure returns (int128) {
    return calculateTradingDelta(oldPoolState, newPoolState, steepness).mul(initialCLevel);
  }

  /**
  * @notice calculate the price of an option using the Median Finance model
  * @param variance TODO
  * @param strike TODO
  * @param price TODO
  * @param timeToMaturity duration of option contract (in years)
  * @param cLevel C-Level of Pool before purchase
  * @param oldPoolState current state of the pool
  * @param newPoolState state of the pool after trade
  * @param steepness state of the pool after trade
  * @param isCall whether to price "call" or "put" option
  * @return TODO
  */
  function quotePrice (
    int128 variance,
    int128 strike,
    int128 price,
    int128 timeToMaturity,
    int128 cLevel,
    int128 oldPoolState,
    int128 newPoolState,
    int128 steepness,
    bool isCall
  ) internal pure returns (int128) {
    return bsPrice(variance, strike, price, timeToMaturity, isCall).mul(
      // slippage coefficient
      ONE_64x64.sub(
        calculateTradingDelta(oldPoolState, newPoolState, steepness)
      ).div(
        newPoolState.sub(oldPoolState).div(oldPoolState).mul(steepness)
      )
    ).mul(
      calculateCLevel(cLevel, oldPoolState, newPoolState, steepness)
    );
  }
}
