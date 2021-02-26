// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/utils/Math.sol';
import { ExponentLib } from "./ExponentLib.sol";
import { FixidityLib } from "./FixidityLib.sol";
import { LogarithmLib } from "./LogarithmLib.sol";

contract OracleMath {
    function rollingAvg(uint256 old, uint256 current, uint256 window) internal pure returns (uint256 updated) {
        return (current - old) / window + old;
    }

    function rollingVar(uint256 old, uint256 last, uint256 oldaverage, uint256 newaverage, uint256 lastvariance, uint256 window) internal pure returns (uint256 updated) {
        return lastvariance + (last - old) * (last + old - newaverage - oldaverage) / (window - 1);
    }

    function rollingStd(uint256 old, uint256 last, uint256 oldaverage, uint256 newaverage, uint256 lastvariance, uint256 window) internal pure returns (uint256 updated) {
        return Math.sqrt(rollingVar(old, last, oldaverage, newaverage, lastvariance, window));
    }

    function bsPrice() internal pure returns (uint256 price) {
        return 1;
    }
}
