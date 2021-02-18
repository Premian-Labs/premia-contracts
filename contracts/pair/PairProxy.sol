// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/contracts/proxy/managed/ManagedProxyOwnable.sol';

import '../core/interfaces/IProxyManager.sol';

/**
 * @title Upgradeable proxy with centrally controlled Pair implementation
 */
contract PairProxy is ManagedProxyOwnable {
  constructor () ManagedProxy(IProxyManager.getPairImplementation.selector) {
    OwnableStorage.layout().owner = msg.sender;
  }
}
