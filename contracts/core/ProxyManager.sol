// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableInternal} from '@solidstate/contracts/access/OwnableInternal.sol';

import {IProxyManager} from './IProxyManager.sol';
import {ProxyManagerStorage} from './ProxyManagerStorage.sol';
import '../pool/PoolProxy.sol';

/**
 * @title Options pair management contract
 * @dev deployed standalone and connected to Premia as diamond facet
 */
contract ProxyManager is IProxyManager, OwnableInternal {
  using ProxyManagerStorage for ProxyManagerStorage.Layout;

  event PoolsDeployment (address asset0, address asset1, address oracle0, address oracle1, address pool0, address pool1);

  /**
   * @notice get address of Pool implementation contract for forwarding via PoolProxy
   * @return implementation address
   */
  function getPoolImplementation () override external view returns (address) {
    return ProxyManagerStorage.layout().poolImplementation;
  }

  /**
   * @notice get address of Pool contract for given assets
   * @param asset0 asset in pool
   * @param asset1 asset in pool
   * @return pair address (zero address if pool does not exist)
   */
  function getPool (
    address asset0,
    address asset1
  ) external view returns (address) {
    return ProxyManagerStorage.layout().getPool(asset0, asset1);
  }

  /**
   * @notice deploy 2 PoolProxy contracts for the pair
   * @param asset0 asset in pair
   * @param asset1 asset in pair
   * @param oracle0 Chainlink price aggregator for asset0
   * @param oracle1 Chainlink price aggregator for asset1
   * TODO: unrestrict
   * @return deployment address
   */
  function deployPools (
    address asset0,
    address asset1,
    address oracle0,
    address oracle1
  ) external onlyOwner returns (address, address) {
    address pool0 = address(new PoolProxy(msg.sender, asset0, asset1, oracle0, oracle1));
    address pool1 = address(new PoolProxy(msg.sender, asset1, asset0, oracle1, oracle0));

    ProxyManagerStorage.layout().setPool(asset0, asset1, pool0);
    ProxyManagerStorage.layout().setPool(asset1, asset0, pool1);

    emit PoolsDeployment(asset0, asset1, oracle0, oracle1, pool0, pool1);

    return (pool0, pool1);
  }
}
