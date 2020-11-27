// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

contract TestTokenSettingsCalculator {
    function getTokenSettings(address token, address denominator) external view returns(uint256 contractSize, uint256 strikePriceIncrement) {
        uint256 _contractSize = 1e18;
        uint256 _strikePriceIncrement = 10e18;


        return (_contractSize, _strikePriceIncrement);
    }
}