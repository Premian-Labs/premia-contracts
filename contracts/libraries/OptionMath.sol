// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';

library OptionMath {
  using ABDKMath64x64 for int128;

  int128 internal constant ONE_64x64 = 0x10000000000000000;
  int128 internal constant THREE_64x64 = 0x30000000000000000;

  // constants used in Choudhury’s approximation of the Black-Scholes CDF
  int128 private constant CDF_CONST_0 = 0x09109f285df452394; // 2260 / 3989
  int128 private constant CDF_CONST_1 = 0x19abac0ea1da65036; // 6400 / 3989
  int128 private constant CDF_CONST_2 = 0x0d3c84b78b749bd6b; // 3300 / 3989

  /**
  * @notice calculate the rolling EMA of a time series
  * @param oldValue64x64 64x64 fixed point representation of previous value
  * @param newValue64x64 64x64 fixed point representation of current value
  * @param window number of periods to use in calculation
  * @return the new EMA value for today
  */
  function rollingEma (
    int128 oldValue64x64,
    int128 newValue64x64,
    uint256 window
  ) internal pure returns (int128) {
    return ABDKMath64x64.divu(2, window + 1).mul(
      newValue64x64.sub(oldValue64x64)
    ).add(oldValue64x64);
  }

  /**
  * @notice calculate the rolling EMA variance of a time series
  * @param oldVariance64x64 64x64 fixed point representation of previous variance
  * @param oldValue64x64 64x64 fixed point representation of previous value
  * @param newValue64x64 64x64 fixed point representation of current value
  * @param window number of periods to use in calculation
  * @return the new variance value for today
  */
  function rollingEmaVariance (
    int128 oldVariance64x64,
    int128 oldValue64x64,
    int128 newValue64x64,
    uint256 window
  ) internal pure returns (int128) {
    int128 alpha = ABDKMath64x64.divu(2, window + 1);

    return ONE_64x64.sub(alpha).mul(
      oldVariance64x64
    ).add(
      alpha.mul(
        newValue64x64.sub(oldValue64x64).pow(2)
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
  * @notice calculate the price of an option using the Black-Scholes model
  * @param emaVarianceAnnualized64x64 TODO
  * @param strike TODO
  * @param price TODO
  * @param timeToMaturity duration of option contract (in years)
  * @param isCall whether to price "call" or "put" option
  * @return 64x64 fixed point representation of Black-Scholes option price
  */
  function bsPrice (
    int128 emaVarianceAnnualized64x64,
    int128 strike,
    int128 price,
    int128 timeToMaturity,
    bool isCall
  ) internal pure returns (int128) {
    // TODO: add require to check variance, price, timeToMaturity > 0, strike => 0.5 * price,  strike <= 2 * price
    int128 cumulativeVariance64x64 = timeToMaturity.mul(emaVarianceAnnualized64x64);
    int128 cumulativeVarianceSqrt64x64 = cumulativeVariance64x64.sqrt();

    int128 d1 = price.div(strike).ln().add(cumulativeVariance64x64 >> 1).div(cumulativeVarianceSqrt64x64);
    int128 d2 = d1.sub(cumulativeVarianceSqrt64x64);

    if (isCall) {
      return price.mul(N(d1)).sub(strike.mul(N(d2)));
    } else {
      return -price.mul(N(-d1)).sub(strike.mul(N(-d2)));
    }
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
    return newPoolState.sub(oldPoolState).div(
      oldPoolState > newPoolState ? oldPoolState : newPoolState
    ).mul(steepness).neg().exp().mul(initialCLevel);
  }

  /**
  * @notice calculate the price of an option using the Median Finance model
  * @param emaVarianceAnnualized64x64 TODO
  * @param strike TODO
  * @param price TODO
  * @param timeToMaturity duration of option contract (in years)
  * @param cLevel C-Level of Pool before purchase
  * @param oldPoolState current state of the pool
  * @param newPoolState state of the pool after trade
  * @param steepness state of the pool after trade
  * @param isCall whether to price "call" or "put" option
  * @return 64x64 fixed point representation of Median option price
  */
  function quotePrice (
    int128 emaVarianceAnnualized64x64,
    int128 strike,
    int128 price,
    int128 timeToMaturity,
    int128 cLevel,
    int128 oldPoolState,
    int128 newPoolState,
    int128 steepness,
    bool isCall
  ) internal pure returns (int128) {
    // TODO: formalize newPoolState < oldPoolState
    int128 deltaPoolState64x64 = newPoolState.sub(oldPoolState).div(oldPoolState).mul(steepness);
    int128 tradingDelta64x64 = deltaPoolState64x64.neg().exp();

    int128 bsPrice64x64 = bsPrice(emaVarianceAnnualized64x64, strike, price, timeToMaturity, isCall);

    return bsPrice64x64.mul(
      // C-Level
      tradingDelta64x64.mul(cLevel)
    ).mul(
      // slippage coefficient
      ONE_64x64.sub(tradingDelta64x64).div(deltaPoolState64x64)
    );
  }
}
