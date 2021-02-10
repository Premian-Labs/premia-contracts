// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import './PoolManagerStorage.sol';

/**
 * @title Option pool management contract
 * @dev inherited component of Pair
 */
abstract contract PoolManager {
  /**
   * @notice get address of Pool implementation contract
   * @dev TODO: override from interface
   * @dev TODO: add to Openhedge contract as facet
   * @return implementation address
   */
  function getPoolImplementation () external view returns (address) {
    return PoolManagerStorage.layout().implementation;
  }
}
