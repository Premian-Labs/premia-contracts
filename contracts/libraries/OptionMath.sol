// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ABDKMath64x64} from 'abdk-libraries-solidity/ABDKMath64x64.sol';

library OptionMath {
  using ABDKMath64x64 for int128;

  int128 internal constant ONE_64x64 = 0x10000000000000000;

  // constants used in Choudhury’s approximation of the Black-Scholes CDF
  int128 internal constant N_CONST_0_64x64 = 0x661e4f765fd8adab; // 0.3989
  int128 internal constant N_CONST_1_64x64 = 0x39db22d0e5604189; // 0.226
  int128 internal constant N_CONST_2_64x64 = 0xa3d70a3d70a3d70a; // 0.64
  int128 internal constant N_CONST_3_64x64 = 0x547ae147ae147ae1; // 0.33

  /**
  * @notice calculates the log return for a given day
  * @param today64x64 today's close
  * @param yesterday64x64 yesterday's close
  * @return log of returns
  * ln(today / yesterday)
  */
  function logreturns (
    int128 today64x64,
    int128 yesterday64x64
  )
  internal
  pure
  returns (int128)
  {
    return today64x64.div(yesterday64x64).ln();
  }

  /**
  * @notice calculates the log return for a given day
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
  * @notice calculates the log return for a given day
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

    return
    ONE_64x64.sub(alpha).mul(
      yesterdayEmaVariance64x64.add(
        alpha.mul(
          today64x64.sub(yesterdayEma64x64).pow(2)
        )
      )
    );
  }

  /**
  * @notice calculates an internal probability for bscholes model
  * @param variance the price from yesterday
  * @param strike the price from today
  * @param price the average from yesterday
  * @param maturity the average from today
  * @return the probability
  */
  function d1(
    int128 variance,
    int128 strike,
    int128 price,
    int128 maturity
  ) internal pure returns (int128) {
    return
    strike.div(price).ln()
    .add(
      maturity.mul(variance / 2)
    )
    .div(
      maturity.mul(variance).sqrt()
    );
  }

  /**
  * @notice calculates approximated CDF
  * @param x random variable
  * @return the approximated CDF of random variable x
  */
  function N(int128 x) internal pure returns (int128) {
    int128 num = x.pow(2).div(ABDKMath64x64.fromInt(2)).neg().exp();
    int128 den =
    N_CONST_1_64x64.add(N_CONST_2_64x64.mul(x)).add(
      N_CONST_3_64x64.mul(x.pow(2).add(ABDKMath64x64.fromInt(3)).sqrt())
    );
    return ONE_64x64.sub(N_CONST_0_64x64.mul(num.div(den)));
  }

  /**
  * @notice xt
  * @param St0 Pool state at t0
  * @param St1 Pool state at t1
  * @return return intermediate viarable Xt
  */
  function Xt(uint256 St0, uint256 St1) internal pure returns (int128) {
    int128 St0 = ABDKMath64x64.fromUInt(St0);
    int128 St1 = ABDKMath64x64.fromUInt(St1);
    return St0.sub(St1).div(St0 > St1 ? St0 : St1);
  }

  /**
  * @notice xt
  * @param St0 Pool state at t0
  * @param St1 Pool state at t1
  * @param Xt Pool state at t0
  * @param steepness Pool state at t1
  * @return return intermediate viarable Xt
  */
  function slippageCoefficient (
    uint256 St0,
    uint256 St1,
    int128 Xt,
    int128 steepness
  ) internal pure returns (int128) {
    return
    ONE_64x64
    .sub(calcTradingDelta(St0, St1, steepness))
    .div(Xt.mul(steepness));
  }

  /**
  * @notice calculates the black scholes price
  * @param variance the price from yesterday
  * @param strike the price from today
  * @param price the average from yesterday
  * @param duration temporal length of option contract
  * @param isCall is this a call option
  * @return the price of the option
  */

  // TODO: add require to check variance, price, duration > 0, strike => 0.5 * price,  strike <= 2 * price
  function bsPrice(
    int128 variance,
    int128 strike,
    int128 price,
    int128 duration,
    bool isCall
  ) internal pure returns (int128) {
    int128 maturity = duration / (365 days);
    int128 d1 = d1(variance, strike, price, maturity);
    int128 d2 = d1.sub(maturity.mul(variance).sqrt());
    if (isCall) return price.mul(N(d1)).sub(strike.mul(N(d2)));
    return strike.mul(N(d2.neg())).sub(price.mul(N(d1.neg())));
  }

  /**
  * @notice calculate new C-Level based on change in liquidity
  * @param St0 liquidity in pool before update
  * @param St1 liquidity in pool after update
  * @param steepness steepness coefficient
  * @return new C-Level
  */
  function calcTradingDelta(
    uint256 St0,
    uint256 St1,
    int128 steepness
  ) internal pure returns (int128) {
    int128 St0 = ABDKMath64x64.fromUInt(St0);
    int128 St1 = ABDKMath64x64.fromUInt(St1);
    return St0.sub(St1).div(St0 > St1 ? St0 : St1).mul(steepness).exp();
  }

  /**
  * @notice calculate new C-Level based on change in liquidity
  * @param oldC previous C-Level
  * @param St0 liquidity in pool before update
  * @param St1 liquidity in pool after update
  * @param steepness steepness coefficient
  * @return new C-Level
  */
  function calculateCLevel(
    int128 oldC,
    uint256 St0,
    uint256 St1,
    int128 steepness
  ) internal pure returns (int128) {
    return calcTradingDelta(St0, St1, steepness).mul(oldC);
  }

  /**
  * @notice calculates the black scholes price
  * @param variance the price from yesterday
  * @param strike the price from today
  * @param price the average from yesterday
  * @param duration temporal length of option contract
  * @param Ct previous C-Level
  * @param St0 current state of the pool
  * @param St1 state of the pool after trade
  * @param steepness state of the pool after trade
  * @return the price of the option
  */
  function quotePrice(
    uint256 variance,
    uint256 strike,
    uint256 price,
    uint256 duration,
    int128 Ct,
    uint256 St0,
    uint256 St1,
    int128 steepness,
    bool isCall
  ) internal pure returns (int128) {
    int128 variance = ABDKMath64x64.fromUInt(variance);
    int128 strike = ABDKMath64x64.fromUInt(strike);
    int128 price = ABDKMath64x64.fromUInt(price);
    int128 duration = ABDKMath64x64.fromUInt(duration);
    int128 slip = slippageCoefficient(St0, St1, Xt(St0, St1), steepness);
    return
    calculateCLevel(Ct, St0, St1, steepness).mul(slip).mul(
      bsPrice(variance, strike, price, duration, isCall)
    );
  }
}
