// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableStorage.sol';

import '../core/ProxyManager.sol';
import '../ManagedProxy.sol';

/**
 * @title Upgradeable proxy with centrally controlled Pair implementation
 * @dev uses Ownable storage location
 */
contract PairProxy is ManagedProxy {
  constructor () {
    OwnableStorage.layout().owner = msg.sender;
  }

  function _implementation () override internal returns (address) {
    return OwnableStorage.layout().owner;
  }
}
