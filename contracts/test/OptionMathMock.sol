// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { OptionMath } from '../libraries/OptionMath.sol';

contract OptionMathMock {
  function logreturns (
    int256 today,
    int256 yesterday
  ) external view returns (int256) {
    return OptionMath.logreturns(today, yesterday);
  }

  function rollingEma (
    int256 _old,
    int256 _current,
    int256 _window
  ) external view returns () {
    return OptionMath.rollingEma(_old, _current, _window);
  }

  function rollingAvg (
    int256 _old,
    int256 _current,
    int256 _window
  ) external view returns (int256) {
    return OptionMath.rollingAvg(_old, _current, _window);
  }

  function rollingVar (
    int256 _yesterday,
    int256 _today,
    int256 _yesterdayaverage,
    int256 _todayaverage,
    int256 _yesterdayvariance,
    int256 _window
  ) external view returns (int256) {
    return OptionMath.rollingVar(_yesterday, _today, _yesterdayaverage, _todayaverage, _yesterdayvariance, _window);
  }

  function p (
    uint256 _variance,
    uint256 _strike,
    uint256 _price,
    int128 _maturity
  ) external view returns (uint256) {
    return OptionMath.p(_variance, _strike, _price, _timestamp);
  }

  function bsPrice (
    uint256 _variance,
    uint256 _strike,
    uint256 _price,
    uint256 _timestamp
  ) external view returns (uint256) {
    return OptionMath.bsPrice(_variance, _strike, _price, _timestamp);
  }

  function cFn (
    uint256 _Ct,
    uint256 _St,
    uint256 _St1
  ) external view returns (uint256) {
    return OptionMath.cFn(_Ct, _St, _St1);
  }

  function pT (
    uint256 _price,
    uint256 _variance,
    uint256 _timestamp,
    uint256 _Ct,
    uint256 _St,
    uint256 _St1
  ) external view returns (uint256) {
    return OptionMath.pT(_price, _variance, _timestamp, _Ct, _St, _St1);
  }

  function approx_pT (
    uint256 _price,
    uint256 _variance,
    uint256 _timestamp,
    uint256 _Ct,
    uint256 _St,
    uint256 _St1
  ) external view returns (uint256) {
    return OptionMath.approx_pT(_price, _variance, _timestamp, _Ct, _St, _St1);
  }

  function approx_Bsch (
    int256 _price,
    int256 _variance,
    uint256 _timestamp
  ) external view returns (int256) {
    return OptionMath.approx_Bsch(_price, _variance, _timestamp);
  }

  function max (
    uint256 a,
    uint256 b
  ) external view returns (uint256) {
    return OptionMath.max(a, b);
  }
}
