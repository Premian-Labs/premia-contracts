// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library ProxyManagerStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'premia.contracts.storage.ProxyManager'
  );

  struct Layout {
    address poolImplementation;
    mapping (address => mapping (address => address)) pools;
  }

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }

  function getPool (
    Layout storage l,
    address asset0,
    address asset1
  ) internal view returns (address) {
    return l.pools[asset0][asset1];
  }

  function setPool (
    Layout storage l,
    address asset0,
    address asset1,
    address pool
  ) internal {
    l.pools[asset0][asset1] = pool;
  }
}
