// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface IPriceProvider {
    function getTokenPrice(address _token) external view returns(uint256);
}