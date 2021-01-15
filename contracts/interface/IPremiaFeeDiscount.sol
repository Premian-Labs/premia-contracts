// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface IPremiaFeeDiscount {
    function getDiscount(address _user) external view returns(uint256);
}