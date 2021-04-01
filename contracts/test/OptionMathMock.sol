// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OptionMath} from "../libraries/OptionMath.sol";

contract OptionMathMock {
  function logreturns(int128 today64x64, int128 yesterday64x64)
  external
  pure
  returns (int128)
  {
    return OptionMath.logreturns(today64x64, yesterday64x64);
  }

  function rollingEma(
    int128 today64x64,
    int128 yesterday64x64,
    uint256 window
  ) external pure returns (int128) {
    return OptionMath.rollingEma(today64x64, yesterday64x64, window);
  }

  function rollingEmaVariance(
    int128 today64x64,
    int128 yesterdayEma64x64,
    int128 yesterdayEmaVariance64x64,
    uint256 window
  ) external pure returns (int128) {
    return
    OptionMath.rollingEmaVariance(
      today64x64,
      yesterdayEma64x64,
      yesterdayEmaVariance64x64,
      window
    );
  }

  function d1(
    int128 variance,
    int128 strike,
    int128 price,
    int128 maturity
  ) external pure returns (int128) {
    return OptionMath.d1(variance, strike, price, maturity);
  }

  function N(int128 x) external pure returns (int128) {
    return OptionMath.N(x);
  }

  function Xt (
    int128 St0,
    int128 St1
  ) external pure returns (int128) {
    return OptionMath.Xt(St0, St1);
  }

  function slippageCoefficient (
    int128 St0,
    int128 St1,
    int128 Xt,
    int128 steepness
  ) external pure returns (int128) {
    return OptionMath.slippageCoefficient(St0, St1, Xt, steepness);
  }

  function bsPrice(
    int128 variance,
    int128 strike,
    int128 price,
    int128 duration,
    bool isCall
  ) external pure returns (int128) {
    return
    OptionMath.bsPrice(variance, strike, price, duration, isCall);
  }

  function calcTradingDelta (
    int128 St0,
    int128 St1,
    int128 steepness
  ) external pure returns (int128) {
    return OptionMath.calcTradingDelta(St0, St1, steepness);
  }

  function calculateCLevel(
    int128 oldC,
    int128 St0,
    int128 St1,
    int128 steepness
  ) external pure returns (int128) {
    return OptionMath.calculateCLevel(oldC, St0, St1, steepness);
  }

  function quotePrice (
    int128 variance,
    int128 strike,
    int128 price,
    int128 duration,
    int128 Ct,
    int128 St0,
    int128 St1,
    int128 steepness,
    bool isCall
  ) external pure returns (int128) {
    return
    OptionMath.quotePrice(
      variance,
      strike,
      price,
      duration,
      Ct,
      St0,
      St1,
      steepness,
      isCall
    );
  }
}
