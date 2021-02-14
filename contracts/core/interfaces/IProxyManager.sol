// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

interface IProxyManager {
  function getPairImplementation () external view returns (address);
  function getPoolImplementation () external view returns (address);
}
