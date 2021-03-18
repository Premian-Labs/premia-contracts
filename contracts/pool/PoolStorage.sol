// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library PoolStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'median.contracts.storage.Pool'
  );

  struct Layout {
    address pair;
    address base;
    address underlying;
    uint liquidity;
    // fixed point representation
    int128 cLevel;
  }

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }
}
