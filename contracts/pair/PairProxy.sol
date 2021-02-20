// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/contracts/proxy/managed/ManagedProxyOwnable.sol';

import '../core/interfaces/IProxyManager.sol';
import '../pool/PoolProxy.sol';

/**
 * @title Upgradeable proxy with centrally controlled Pair implementation
 */
contract PairProxy is ManagedProxyOwnable {
  constructor (
    address asset0,
    address asset1
  ) ManagedProxy(IProxyManager.getPairImplementation.selector) {
    OwnableStorage.layout().owner = msg.sender;
    new PoolProxy(msg.sender, asset0, asset1);
    new PoolProxy(msg.sender, asset1, asset0);
  }
}
