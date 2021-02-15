// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/contracts/proxy/managed/ManagedProxyOwnable.sol';

import '../core/interfaces/IProxyManager.sol';

/**
 * @title Upgradeable proxy with centrally controlled Pool implementation
 */
contract PoolProxy is ManagedProxyOwnable {
  constructor (
    address owner
  ) ManagedProxy(IProxyManager.getPoolImplementation.selector) {
    OwnableStorage.layout().owner = owner;
  }
}
