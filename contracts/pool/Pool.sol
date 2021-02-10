// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableInternal.sol';

/**
 * @title Openhedge option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is OwnableInternal {
  /**
   * @notice initialize proxy storage
   * @param base asset used as unit of account
   * @param underlying asset optioned
   */
  function initialize (
    address base,
    address underlying
  ) external onlyOwner {
    // TODO: initialize
  }
}
