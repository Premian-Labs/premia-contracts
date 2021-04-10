// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPremiaMiningV2 {
    struct Pair {
        address token;
        address denominator;
        bool useToken;
    }

    function deposit(address _user, Pair memory _pair, uint256 _amount, uint256 _lockExpiration) external;
}
