// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IProxyManager {
    function getPoolList() external view returns (address[] memory);
}
