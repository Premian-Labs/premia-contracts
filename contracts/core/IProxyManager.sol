// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IProxyManager {
  function getPoolImplementation () external view returns (address);
}
