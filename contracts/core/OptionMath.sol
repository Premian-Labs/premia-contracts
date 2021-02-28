// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/utils/Math.sol';
import { ABDKMath64x64 } from "./libraries/ABDKMath64x64.sol";

contract OptionMath {

    function logreturns(uint256 close, uint256 close_1back) internal pure returns (uint256){
        return uint256(ABDKMath64x64.ln(int256(close/close_1back)));
    }

    function rollingEma(uint256 _old, uint256 _current, uint256 alpha) internal pure returns (uint256){
        return alpha * (_current - _old) + _old;
    }

    function rollingAvg(uint256 _old, uint256 _current, uint256 _window) internal pure returns (uint256) {
        return _old + (_current - _old)/_window;
    }

    function rollingVar(uint256 _old, uint256 _last, uint256 _oldaverage, uint256 _newaverage, uint256 _lastvariance, uint256 _window) internal pure returns (uint256) {
        return _lastvariance + (_last - _old) * (_last - _newaverage + _old - _oldaverage)/(_window - 1);
    }

    function p(uint256 _var, uint256 _strike, uint256 _price, uint256 _days) internal pure returns (uint256) {
        return (uint256(ABDKMath64x64.ln(int256(_strike/_price))) + _var/2 * _days)/ABDKMath64x64.sqrt(_var*_days);
    }

    function bsPrice(uint256 _var, uint256 _strike, uint256 _price, uint256 _timestamp) internal view returns (uint256) {
        require(_timestamp > block.timestamp, 'Option in the past');
        uint256 maturity = (_timestamp - block.timestamp) / (1 days);
        uint256 prob = p(_var, _strike, _price, maturity);
        return _price * prob - _strike * uint256(ABDKMath64x64.exp(int256(maturity))) * prob;
    }

    function slippageFn(uint256 _Ct, uint256 _St, uint256 _St1) internal pure returns (uint256){
        int256 exp = int256((_St1 - _St) / max(_St, _St1));
        return _Ct * uint256(ABDKMath64x64.inv(ABDKMath64x64.exp(exp)));
    }

    function pT(uint256 _var, uint256 _strike, uint256 _price, uint256 _timestamp, uint256 _Ct, uint256 _St, uint256 _St1) internal view returns (uint256) {
        return slippageFn(_Ct, _St, _St1) * bsPrice(_var, _strike, _price, _timestamp);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
