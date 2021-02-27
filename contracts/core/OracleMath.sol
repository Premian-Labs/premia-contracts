// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/utils/Math.sol';
import { ExponentLib } from "./libraries/ExponentLib.sol";
import { FixidityLib } from "./libraries/FixidityLib.sol";
import { LogarithmLib } from "./libraries/LogarithmLib.sol";

contract OracleMath {

    function logreturns(uint256 close, uint256 close_1back) internal pure returns (uint256){
        return uint256(LogarithmLib.log_b(10, int256(close/close_1back)));
    }

    function rollingEma(uint256 _old, uint256 _current, uint256 alpha) internal pure returns (uint256){
        return alpha * (_current - _old) + _old;
    }

    function rollingAvg(uint256 _old, uint256 _current, uint256 _window) internal pure returns (uint256 updated) {
        return _old + (_current - _old)/_window;
        // return old.add(current.sub(old).div(window));
    }

    function rollingVar(uint256 _old, uint256 _last, uint256 _oldaverage, uint256 _newaverage, uint256 _lastvariance, uint256 _window) internal pure returns (uint256 updated) {
        return _lastvariance + (_last - _old) * (_last - _newaverage + _old - _oldaverage)/(_window - 1);
        // return lastvariance.add(last.sub(old).mul(last.sub(newaverage).add(old).sub(oldaverage).div(window.sub(1))));
    }

    function rollingStd(uint256 _old, uint256 _last, uint256 _oldaverage, uint256 _newaverage, uint256 _lastvariance, uint256 _window) internal pure returns (uint256 updated) {
        return sqrt(rollingVar(_old, _last, _oldaverage, _newaverage, _lastvariance, _window));
    }

    function d1(uint256 _std, uint256 _strike, uint256 _price, uint256 _time) internal pure returns (uint256) {
        // return (uint256(LogarithmLib.ln(int256(_strike/_price))) + (_std**2)/2 * _time)/sqrt(_std**2*_time);
        return 1;
    }

    function d2(uint256 _std, uint256 _strike, uint256 _price, uint256 _time) internal pure returns (uint256) {
        return 1;
    }

    function leftSide(uint256 _std, uint256 _strike, uint256 _price, uint256 _time) internal pure returns (uint256) {
        return (_price * d1(_std, _strike, _price, _time));
        // return price.mul(d1(std, strike, price, time));
    }

    function e(uint256 _time) internal pure returns (uint256){
        return uint256(ExponentLib.powerE(int256(_time)));
    }

    function rightSide(uint256 _std, uint256 _strike, uint256 _price, uint256 _time) internal pure returns (uint256) {
        return (_strike * e(_time) * d1(_std, _strike, _price, _time));
        // return strike.mul(e(time).mul(d2(std, strike, price, time)));
    }

    function bsPrice(uint256 _std, uint256 _strike, uint256 _price, uint256 _time) internal pure returns (uint256) {
        // return leftSide(_std, _strike, _price, _time) - rightSide(_std, _strike, _price, _time);
        // return leftSide(std, strike, price, time).sub(rightSide(std, strike, price, time));
        return 1;
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
