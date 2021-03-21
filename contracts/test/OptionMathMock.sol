// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OptionMath} from "../libraries/OptionMath.sol";

contract OptionMathMock {
    /**
     * @notice calculates the log return for a given day
     * @param _today todays close
     * @param _yesterday yesterdays close
     * @return log of returns
     * ln( today / yesterday)
     */
    function logreturns(int256 _today, int256 _yesterday)
        external
        pure
        returns (int256)
    {
        return OptionMath.logreturns(_today, _yesterday);
    }

    /**
     * @notice calculates the log return for a given day
     * @param _old the price from yesterday
     * @param _current today's price
     * @param _window the period for the EMA average
     * @return the new EMA value for today
     * alpha * (current - old ) + old
     */
    function rollingEma(
        int256 _old,
        int256 _current,
        int256 _window
    ) external pure returns (int256) {
        return OptionMath.rollingEma(_old, _current, _window);
    }

    /**
     * @notice calculates the log return for a given day
     * @param _today the price from today
     * @param _yesterdayema the average from yesterday
     * @param _yesterdayemavariance the variation from yesterday
     * @param _window the period for the average
     * @return the new variance value for today
     * (1 - a)(EMAVar t-1  +  a( x t - EMA t-1)^2)
     */
    function rollingEmaVar(
        int256 _today,
        int256 _yesterdayema,
        int256 _yesterdayemavariance,
        int256 _window
    ) external pure returns (int256) {
        return
            OptionMath.rollingEmaVar(
                _today,
                _yesterdayema,
                _yesterdayemavariance,
                _window
            );
    }

    /**
     * @notice calculates an internal probability for bscholes model
     * @param _variance the price from yesterday
     * @param _strike the price from today
     * @param _price the average from yesterday
     * @param _maturity the average from today
     * @return the probability
     */
    function d1(
        int128 _variance,
        int128 _strike,
        int128 _price,
        int128 _maturity
    ) external pure returns (int128) {
        return OptionMath.d1(_variance, _strike, _price, _maturity);
    }

    /**
     * @notice calculates approximated CDF
     * @param _x random variable
     * @return the approximated CDF of random variable x
     */
    function N(int128 _x) external pure returns (int128) {
        return OptionMath.N(_x);
    }

    /**
     * @notice xt
     * @param _St0 Pool state at t0
     * @param _St1 Pool state at t1
     * @return return intermediate viarable Xt
     */
    function Xt(uint256 _St0, uint256 _St1) external pure returns (int128) {
        return OptionMath.Xt(_St0, _St1);
    }

    /**
     * @notice xt
     * @param _St0 Pool state at t0
     * @param _St1 Pool state at t1
     * @param _Xt Pool state at t0
     * @param _steepness Pool state at t1
     * @return return intermediate viarable Xt
     */
    function SlippageCoef(
        uint256 _St0,
        uint256 _St1,
        int128 _Xt,
        int128 _steepness
    ) external pure returns (int128) {
        return OptionMath.SlippageCoef(_St0, _St1, _Xt, _steepness);
    }

    /**
     * @notice calculates the black scholes price
     * @param _variance the price from yesterday
     * @param _strike the price from today
     * @param _price the average from yesterday
     * @param _duration temporal length of option contract
     * @param _isCall is this a call option
     * @return the price of the option
     */
    function bsPrice(
        int128 _variance,
        int128 _strike,
        int128 _price,
        int128 _duration,
        bool _isCall
    ) external pure returns (int128) {
        return
            OptionMath.bsPrice(_variance, _strike, _price, _duration, _isCall);
    }

    /**
     * @notice calculate new C-Level based on change in liquidity
     * @param _St0 liquidity in pool before update
     * @param _St1 liquidity in pool after update
     * @param _steepness steepness coefficient
     * @return new C-Level
     */
    function calcTradingDelta(
        uint256 _St0,
        uint256 _St1,
        int128 _steepness
    ) external pure returns (int128) {
        return OptionMath.calcTradingDelta(_St0, _St1, _steepness);
    }

    /**
     * @notice calculate new C-Level based on change in liquidity
     * @param _oldC previous C-Level
     * @param _St0 liquidity in pool before update
     * @param _St1 liquidity in pool after update
     * @param _steepness steepness coefficient
     * @return new C-Level
     */
    function calculateCLevel(
        int128 _oldC,
        uint256 _St0,
        uint256 _St1,
        int128 _steepness
    ) external pure returns (int128) {
        return OptionMath.calculateCLevel(_oldC, _St0, _St1, _steepness);
    }

    /**
     * @notice calculates the black scholes price
     * @param _variance the price from yesterday
     * @param _strike the price from today
     * @param _price the average from yesterday
     * @param _duration temporal length of option contract
     * @param _Ct previous C-Level
     * @param _St0 current state of the pool
     * @param _St1 state of the pool after trade
     * @param _steepness state of the pool after trade
     * @return the price of the option
     */
    function quotePrice(
        uint256 _variance,
        uint256 _strike,
        uint256 _price,
        uint256 _duration,
        int128 _Ct,
        uint256 _St0,
        uint256 _St1,
        int128 _steepness,
        bool _isCall
    ) external pure returns (int128) {
        return
            OptionMath.quotePrice(
                _variance,
                _strike,
                _price,
                _duration,
                _Ct,
                _St0,
                _St1,
                _steepness,
                _isCall
            );
    }
}
