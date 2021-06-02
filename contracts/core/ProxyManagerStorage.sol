// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library ProxyManagerStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'median.contracts.storage.ProxyManager'
  );

  struct Layout {
    address pairImplementation;
    address poolImplementation;
    mapping (address => mapping (address => address)) pairs;
  }

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }

  function getPair (
    Layout storage l,
    address asset0,
    address asset1
  ) internal view returns (address) {
    if (asset0 > asset1) {
      (asset0, asset1) = (asset1, asset0);
    }

    return l.pairs[asset0][asset1];
  }

  function setPair (
    Layout storage l,
    address asset0,
    address asset1,
    address pair
  ) internal {
    if (asset0 > asset1) {
      (asset0, asset1) = (asset1, asset0);
    }

    l.pairs[asset0][asset1] = pair;
  }
}
