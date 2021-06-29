// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { OptionMath } from '../libraries/OptionMath.sol';

contract OptionMathMock is OptionMath {
  function decay (
    uint256 oldTimestamp,
    uint256 newTimestamp
  ) external pure returns (int128) {
    return _decay(oldTimestamp, newTimestamp);
  }

  function unevenRollingEma (
    int128 oldEma64x64,
    int128 logReturns64x64,
    uint256 oldTimestamp,
    uint256 newTimestamp
  ) external pure returns (int128) {
    return _unevenRollingEma(
      oldEma64x64,
      logReturns64x64,
      oldTimestamp,
      newTimestamp
    );
  }

  function N (
    int128 x
  ) external pure returns (int128) {
    return _N(x);
  }

  function bsPrice (
    int128 variance,
    int128 strike,
    int128 price,
    int128 timeToMaturity,
    bool isCall
  ) external pure returns (int128) {
    return _bsPrice(variance, strike, price, timeToMaturity, isCall);
  }
}
