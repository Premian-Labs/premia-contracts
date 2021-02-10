// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableInternal.sol';

import '../pool/Pool.sol';
import '../pool/PoolProxy.sol';
import './PoolManager.sol';

/**
 * @title Openhedge options pair
 * @dev deployed standalone and referenced by PairProxy
 */
contract Pair is OwnableInternal, PoolManager {
  /**
   * @notice initialize proxy storage
   * @param asset0 asset in pair
   * @param asset1 asset in pair
   */
  function initialize (
    address asset0,
    address asset1
  ) external onlyOwner {
    if (asset0 > asset1) {
      (asset0, asset1) = (asset1, asset0);
    }

    PoolProxy pool0 = new PoolProxy();
    Pool(address(pool0)).initialize(asset0, asset1);
    PoolProxy pool1 = new PoolProxy();
    Pool(address(pool1)).initialize(asset1, asset0);

    // TODO: set pool implementation
  }
}
