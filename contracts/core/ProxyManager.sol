// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';

import './IProxyManager.sol';
import './ProxyManagerStorage.sol';

/**
 * @title Options pair management contract
 * @dev deployed standalone and connected to Median as diamond facet
 */
contract ProxyManager is IProxyManager, OwnableInternal {
  using ProxyManagerStorage for ProxyManagerStorage.Layout;

  function getOptionImplementation() override external view returns (address) {
    return ProxyManagerStorage.layout().optionImplementation;
  }

  function getMarketImplementation() override external view returns (address) {
    return ProxyManagerStorage.layout().marketImplementation;
  }
}
