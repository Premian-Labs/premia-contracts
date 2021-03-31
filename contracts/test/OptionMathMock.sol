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
        int256 _today,
        int256 _yesterdayema,
        int256 _yesterdayemavariance,
        uint256 _window
    ) external pure returns (int256) {
        return
            OptionMath.rollingEmaVariance(
                _today,
                _yesterdayema,
                _yesterdayemavariance,
                _window
            );
    }

    function d1(
        int128 _variance,
        int128 _strike,
        int128 _price,
        int128 _maturity
    ) external pure returns (int128) {
        return OptionMath.d1(_variance, _strike, _price, _maturity);
    }

    function N(int128 _x) external pure returns (int128) {
        return OptionMath.N(_x);
    }

    function Xt(uint256 _St0, uint256 _St1) external pure returns (int128) {
        return OptionMath.Xt(_St0, _St1);
    }

    function SlippageCoef(
        uint256 _St0,
        uint256 _St1,
        int128 _Xt,
        int128 _steepness
    ) external pure returns (int128) {
        return OptionMath.SlippageCoef(_St0, _St1, _Xt, _steepness);
    }

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

    function calcTradingDelta(
        uint256 _St0,
        uint256 _St1,
        int128 _steepness
    ) external pure returns (int128) {
        return OptionMath.calcTradingDelta(_St0, _St1, _steepness);
    }

    function calculateCLevel(
        int128 _oldC,
        uint256 _St0,
        uint256 _St1,
        int128 _steepness
    ) external pure returns (int128) {
        return OptionMath.calculateCLevel(_oldC, _St0, _St1, _steepness);
    }

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
