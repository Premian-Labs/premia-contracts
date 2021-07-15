// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IProxyManagerOld {
    function getOptionImplementation() external view returns (address);

    function getMarketImplementation() external view returns (address);
}
