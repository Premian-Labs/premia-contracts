// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPremiaMiningV2 {
    function deposit(address _user, address _token, uint256 _amount, uint256 _lockExpiration) external;
}
