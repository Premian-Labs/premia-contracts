// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ABDKMath64x64} from "../libraries/ABDKMath64x64.sol";

library OptionMath {
    using ABDKMath64x64 for int128;

    /**
     * @notice calculates the log return for a given day
     * @param today todays close
     * @param yesterday yesterdays close
     * @return log of returns
     */
    function logreturns(int256 today, int256 yesterday)
        internal
        pure
        returns (int256)
    {
        return ABDKMath64x64.divi(today, yesterday).ln().to128x128();
    }

    /**
     * @notice calculates the log return for a given day
     * @param _old the price from yesterday
     * @param _current today's price
     * @param _window the period for the EMA average
     * @return the new EMA value for today
     */
    function rollingEma(
        int256 _old,
        int256 _current,
        int256 _window
    ) internal pure returns (int256) {
        int128 alpha = ABDKMath64x64.divi(2, (1 + _window));
        return alpha.muli(_current - _old) + _old;
        // return ABDKMath64x64.muli(alpha, (_current - _old)) + _old;
    }

    /**
     * @notice calculates the log return for a given day
     * @param _old the average price from yesterday
     * @param _current today's price
     * @param _window the period for the average
     * @return the new average value for today
     */
    function rollingAvg(
        int256 _old,
        int256 _current,
        int256 _window
    ) internal pure returns (int256) {
        return _old + ABDKMath64x64.divi(_current - _old, _window).to128x128();
    }

    /**
     * @notice calculates the log return for a given day
     * @param _yesterday the price from yesterday
     * @param _today the price from today
     * @param _yesterdayaverage the average from yesterday
     * @param _todayaverage the average from today
     * @param _yesterdayvariance the variation from yesterday
     * @param _window the period for the average
     * @return the new variance value for today
     */
    function rollingVar(
        int256 _yesterday,
        int256 _today,
        int256 _yesterdayaverage,
        int256 _todayaverage,
        int256 _yesterdayvariance,
        int256 _window
    ) internal pure returns (int256) {
        return
            _yesterdayvariance +
            ABDKMath64x64
                .divi(
                (_today - _yesterday) *
                    (_today - _todayaverage + _yesterday - _yesterdayaverage),
                (_window - 1)
            )
                .to128x128();
    }

    /**
     * @notice calculates an internal probability for bscholes model
     * @param _variance the price from yesterday
     * @param _strike the price from today
     * @param _price the average from yesterday
     * @param _maturity the average from today
     * @return the probability
     */
    function p(
        uint256 _variance,
        uint256 _strike,
        uint256 _price,
        int128 _maturity
    ) internal pure returns (uint256) {
        return
            uint256(
                ABDKMath64x64.toUInt(
                    ABDKMath64x64.ln(ABDKMath64x64.divu(_strike, _price)) +
                        ABDKMath64x64.div(
                            ABDKMath64x64.mul(
                                _maturity,
                                ABDKMath64x64.divu(_variance, 2)
                            ),
                            ABDKMath64x64.sqrt(
                                ABDKMath64x64.fromUInt(
                                    ABDKMath64x64.mulu(_maturity, _variance)
                                )
                            )
                        )
                )
            );
    }

    /**
     * @notice calculates the black scholes price
     * @param _variance the price from yesterday
     * @param _strike the price from today
     * @param _price the average from yesterday
     * @param _duration temporal length of option contract
     * @return the price of the option
     */
    function bsPrice(
        uint256 _variance,
        uint256 _strike,
        uint256 _price,
        uint256 _duration
    ) internal view returns (uint256) {
        int128 maturity = ABDKMath64x64.divu(_duration, (365 days));
        uint256 prob = p(_variance, _strike, _price, maturity);
        return
            _price *
            prob -
            _strike *
            ABDKMath64x64.toUInt((ABDKMath64x64.exp(maturity))) *
            prob;
    }

    /**
     * @notice slippage function
     * @param _Ct previous C value
     * @param _St current state of the pool
     * @param _St1 state of the pool after trade
     * @return new C value
     */
    function cFn(
        uint256 _Ct,
        uint256 _St,
        uint256 _St1
    ) internal pure returns (uint256) {
        uint256 exp = (_St1 - _St) / max(_St, _St1);
        return ABDKMath64x64.fromUInt(exp).exp().inv().mulu(_Ct);
    }

    /**
     * @notice calculates the black scholes price
     * @param _variance the price from yesterday
     * @param _strike the price from today
     * @param _price the average from yesterday
     * @param _duration temporal length of option contract
     * @param _Ct previous C value
     * @param _St current state of the pool
     * @param _St1 state of the pool after trade
     * @return the price of the option
     */
    function pT(
        uint256 _variance,
        uint256 _strike,
        uint256 _price,
        uint256 _duration,
        uint256 _Ct,
        uint256 _St,
        uint256 _St1
    ) internal view returns (uint256) {
        return
            cFn(_Ct, _St, _St1) *
            bsPrice(_variance, _strike, _price, _duration);
    }

    /**
     * @notice calculates the approximated blackscholes model
     * @param _price the price today
     * @param _variance the variance from today
     * @param _duration temporal length of option contract
     * @param _Ct previous C value
     * @param _St current state of the pool
     * @param _St1 state of the pool after trade
     * @return an approximation for the price of a BS option
     */
    function approx_pT(
        uint256 _price,
        uint256 _variance,
        uint256 _duration,
        uint256 _Ct,
        uint256 _St,
        uint256 _St1
    ) internal view returns (uint256) {
        int128 maturity = ABDKMath64x64.divu(_duration, (365 days));
        return
            maturity.sqrt().mulu(cFn(_Ct, _St, _St1)) *
            ABDKMath64x64.divu(4, 10).mulu(_price) *
            _variance;
    }

    /**
     * @notice calculates the approximated blackscholes model
     * @param _price the price today
     * @param _variance the variance from today
     * @param _duration temporal length of option contract
     * @return an approximation for the price of a BS option
     */
    function approx_Bsch(
        int256 _price,
        int256 _variance,
        uint256 _duration
    ) internal view returns (int256) {
        int128 maturity = ABDKMath64x64.divu(_duration, (365 days));
        return
            maturity.sqrt() *
            ABDKMath64x64.divi(4, 10).muli(_price) *
            _variance;
    }

    /**
     * @notice takes two unsigned integers and returns the max
     * @param a the first number to check
     * @param b the second number to check
     * @return return the max of a, b
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
