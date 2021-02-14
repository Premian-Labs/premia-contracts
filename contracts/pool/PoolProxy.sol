// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableStorage.sol';

import '../core/interfaces/IProxyManager.sol';
import '../Proxy.sol';

/**
 * @title Upgradeable proxy with centrally controlled Pool implementation
 * @dev uses Ownable storage location
 */
contract PoolProxy is Proxy {
  constructor (
    address owner
  ) {
    OwnableStorage.layout().owner = owner;
  }

  function _implementation () override internal returns (address) {
    return IProxyManager(OwnableStorage.layout().owner).getPoolImplementation();
  }
}
