// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface TokenSettingsCalculator {
    function getTokenSettings(address token, address denominator) external view returns(uint256 contractSize, uint256 strikePriceIncrement);
}