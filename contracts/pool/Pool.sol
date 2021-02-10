// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableInternal.sol';

abstract contract Pool is OwnableInternal {
  function initialize (
    address base,
    address underlying
  ) external onlyOwner {
    // TODO: initialize
  }
}
