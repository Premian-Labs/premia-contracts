// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ABDKMath64x64} from "../libraries/ABDKMath64x64.sol";

library OptionMath {
    using ABDKMath64x64 for int128;

    /**
     * @notice calculates the log return for a given day
     * @param _today todays close
     * @param _yesterday yesterdays close
     * @return log of returns
     * ln( today / yesterday)
     */
    function logreturns(int256 _today, int256 _yesterday)
        internal
        pure
        returns (int256)
    {
        int128 today64x64 = ABDKMath64x64.fromInt(_today);
        int128 yesterday64x64 = ABDKMath64x64.fromInt(_yesterday);
        return ABDKMath64x64.toInt(today64x64.div(yesterday64x64).ln());
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
    ) internal pure returns (int256) {
        int128 alpha = ABDKMath64x64.fromInt(2).divi(1 + _window);
        int128 current64x64 = ABDKMath64x64.fromInt(_current);
        int128 old64x64 = ABDKMath64x64.fromInt(_old);
        return
            ABDKMath64x64.toInt(
                alpha.mul(current64x64.sub(old64x64)).add(old64x64)
            );
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
    ) internal pure returns (int256) {
        int128 alpha = ABDKMath64x64.fromInt(2).divi(1 + _window);
        int128 yesterdayemavariance64x64 =
            ABDKMath64x64.fromInt(_yesterdayemavariance);
        int128 yesterdayema = ABDKMath64x64.fromInt(_yesterdayema);
        int128 today64x64 = ABDKMath64x64.fromInt(_today);
        return
            ABDKMath64x64.ONE_64x64.sub(alpha).mul(
                yesterdayemavariance64x64.add(
                    alpha.mul(today64x64.sub(yesterdayema)).pow(2)
                )
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
    ) internal pure returns (int128) {
        return
            _strike.div(_price).ln().add(
                _maturity.mul(_variance.divi(2)).div(
                    _maturity.mul(_variance).sqrt()
                )
            );
    }

    /**
     * @notice calculates approximated CDF
     * @param _x random variable
     * @return the approximated CDF of random variable x
     */
    function N(int128 _x) internal pure returns (int128) {
        int128 const_0 = ABDKMath64x64.fromInt(3989).divi(10000);
        int128 const_1 = ABDKMath64x64.fromInt(226).divi(1000);
        int128 const_2 = ABDKMath64x64.fromInt(64).divi(100);
        int128 const_3 = ABDKMath64x64.fromInt(33).divi(100);
        int128 num = _x.pow(2).div(ABDKMath64x64.fromInt(2)).neg().exp();
        int128 den =
            const_1.add(const_2.mul(_x)).add(
                const_3.mul(_x.pow(2).add(ABDKMath64x64.fromInt(3)).sqrt())
            );
        return ABDKMath64x64.ONE_64x64.sub(const_0.mul(num.div(den)));
    }

    /**
     * @notice xt
     * @param _St0 Pool state at t0
     * @param _St1 Pool state at t1
     * @return return intermediate viarable Xt
     */
    function Xt(uint256 _St0, uint256 _St1) internal pure returns (int128) {
        int128 St0 = ABDKMath64x64.fromUInt(_St0);
        int128 St1 = ABDKMath64x64.fromUInt(_St1);
        return St0.sub(St1).div(St0 > St1 ? St0 : St1);
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
    ) internal pure returns (int128) {
        return
            ABDKMath64x64
                .ONE_64x64
                .sub(calcTradingDelta(_St0, _St1, _steepness))
                .div(_Xt.mul(_steepness));
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
    ) internal pure returns (int128) {
        int128 maturity = _duration.divi(365 days);
        int128 d1 = d1(_variance, _strike, _price, maturity);
        int128 d2 = d1.sub(maturity.mul(_variance).sqrt());
        if (_isCall) return _price.mul(N(d1)).sub(_strike.mul(N(d2)));
        return _strike.mul(N(d2.neg())).sub(_price.mul(N(d1.neg())));
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
    ) internal pure returns (int128) {
        int128 St0 = ABDKMath64x64.fromUInt(_St0);
        int128 St1 = ABDKMath64x64.fromUInt(_St1);
        return St0.sub(St1).div(St0 > St1 ? St0 : St1).mul(_steepness).exp();
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
    ) internal pure returns (int128) {
        return calcTradingDelta(_St0, _St1, _steepness).mul(_oldC);
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
    ) internal pure returns (int128) {
        int128 variance = ABDKMath64x64.fromUInt(_variance);
        int128 strike = ABDKMath64x64.fromUInt(_strike);
        int128 price = ABDKMath64x64.fromUInt(_price);
        int128 duration = ABDKMath64x64.fromUInt(_duration);
        int128 xt = Xt(_St0, _St1);
        int128 slip = SlippageCoef(_St0, _St1, xt, _steepness);
        return
            calculateCLevel(_Ct, _St0, _St1, _steepness).mul(slip).mul(
                bsPrice(variance, strike, price, duration, _isCall)
            );
    }
}
