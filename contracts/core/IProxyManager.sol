// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IProxyManager {
  function getOptionImplementation() external view returns (address);
  function getMarketImplementation() external view returns (address);
}
