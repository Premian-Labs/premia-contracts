// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/utils/Math.sol';
import '@solidstate/contracts/contracts/utils/SafeMath.sol';

contract OracleMath {
    using SafeMath for uint256;

    function rollingAvg(uint256 old, uint256 current, uint256 window) internal pure returns (uint256 updated) {
        return old.add(current.sub(old).div(window));
    }

    function rollingVar(uint256 old, uint256 last, uint256 oldaverage, uint256 newaverage, uint256 lastvariance, uint256 window) internal pure returns (uint256 updated) {
        return lastvariance.add(last.sub(old).mul(last.sub(newaverage).add(old).sub(oldaverage).div(window.sub(1))));
    }

    function rollingStd(uint256 old, uint256 last, uint256 oldaverage, uint256 newaverage, uint256 lastvariance, uint256 window) internal pure returns (uint256 updated) {
        return Math.sqrt(rollingVar(old, last, oldaverage, newaverage, lastvariance, window));
    }

    function bsPrice() internal pure returns (uint256 price) {
        return 1;
    }
}
