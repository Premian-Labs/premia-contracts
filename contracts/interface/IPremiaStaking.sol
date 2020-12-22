// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface IPremiaStaking {
    function getDiscount(address _user) external returns(uint256);
}