// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableInternal.sol';

/**
 * @title Openhedge options pair
 * @dev deployed standalone and referenced by PairProxy
 */
contract Pair is OwnableInternal {
  /**
   * @notice initialize proxy
   * TODO: assets
   */
  function initialize (
    address,
    address
  ) external onlyOwner {
    // TODO: deploy pools
  }
}
