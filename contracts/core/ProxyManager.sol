// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/contracts/access/OwnableInternal.sol';

import '../pair/Pair.sol';
import '../pair/PairProxy.sol';
import './interfaces/IProxyManager.sol';
import './ProxyManagerStorage.sol';

/**
 * @title Options pair management contract
 * @dev deployed standalone and connected to Openhedge as diamond facet
 */
contract ProxyManager is IProxyManager, OwnableInternal {
  using ProxyManagerStorage for ProxyManagerStorage.Layout;

  event PairDeployment (address pair);

  /**
   * @notice get address of Pair implementation contract for forwarding via PairProxy
   * @return implementation address
   */
  function getPairImplementation () override external view returns (address) {
    return ProxyManagerStorage.layout().pairImplementation;
  }

  /**
   * @notice get address of Pool implementation contract for forwarding via PoolProxy
   * @return implementation address
   */
  function getPoolImplementation () override external view returns (address) {
    return ProxyManagerStorage.layout().poolImplementation;
  }

  /**
   * @notice get address of Pair contract for given assets
   * @param asset0 asset in pair
   * @param asset1 asset in pair
   * @return pair address (zero address if pair does not exist)
   */
  function getPair (
    address asset0,
    address asset1
  ) external view returns (address) {
    return ProxyManagerStorage.layout().getPair(asset0, asset1);
  }

  /**
   * @notice deploy PairProxy contract
   * @param asset0 asset in pair
   * @param asset1 asset in pair
   * TODO: unrestrict
   * @return deployment address
   */
  function deployPair (
    address asset0,
    address asset1
  ) external onlyOwner returns (address) {
    PairProxy pair = new PairProxy(asset0, asset1);
    ProxyManagerStorage.layout().setPair(asset0, asset1, address(pair));
    emit PairDeployment(address(pair));
    return address(pair);
  }
}
