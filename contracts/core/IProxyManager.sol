// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IProxyManager {
  function getPairImplementation () external view returns (address);
  function getPoolImplementation () external view returns (address);
}
