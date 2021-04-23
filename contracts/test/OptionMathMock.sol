// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { OptionMath } from '../libraries/OptionMath.sol';

contract OptionMathMock {
  function decay (
    uint256 oldTimestamp,
    uint256 newTimestamp
  ) internal pure returns (int128) {
    return OptionMath.decay(oldTimestamp, newTimestamp);
  }

  function unevenRollingEma (
    int128 oldEma64x64,
    int128 oldValue64x64,
    int128 newValue64x64,
    uint256 oldTimestamp,
    uint256 newTimestamp
  ) internal pure returns (int128) {
    return OptionMath.unevenRollingEma(
      oldEma64x64,
      oldValue64x64,
      newValue64x64,
      oldTimestamp,
      newTimestamp
    );
  }

  function unevenRollingEmaVariance (
    int128 oldEma64x64,
    int128 oldEmaVariance64x64,
    int128 oldValue64x64,
    int128 newValue64x64,
    uint256 oldTimestamp,
    uint256 newTimestamp
  ) internal pure returns (int128) {
    return OptionMath.unevenRollingEmaVariance(
      oldEma64x64,
      oldEmaVariance64x64,
      oldValue64x64,
      newValue64x64,
      oldTimestamp,
      newTimestamp
    );
  }

  function N (
    int128 x
  ) external pure returns (int128) {
    return OptionMath.N(x);
  }

  function bsPrice (
    int128 variance,
    int128 strike,
    int128 price,
    int128 timeToMaturity,
    bool isCall
  ) external pure returns (int128) {
    return OptionMath.bsPrice(variance, strike, price, timeToMaturity, isCall);
  }

  function calculateCLevel (
    int128 initialCLevel,
    int128 oldPoolState,
    int128 newPoolState,
    int128 steepness
  ) external pure returns (int128) {
    return OptionMath.calculateCLevel(initialCLevel, oldPoolState, newPoolState, steepness);
  }

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
  ) external pure returns (int128, int128) {
    return OptionMath.quotePrice(
      variance,
      strike,
      price,
      timeToMaturity,
      cLevel,
      oldPoolState,
      newPoolState,
      steepness,
      isCall
    );
  }
}
