// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface ITokenSettingsCalculator {
    function getTokenSettings(address token, address denominator) external view returns(uint256 contractSize, uint256 strikePriceIncrement);
}