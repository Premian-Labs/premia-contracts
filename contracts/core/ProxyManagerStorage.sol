// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

library ProxyManagerStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'openhedge.contracts.storage.ProxyManager'
  );

  struct Layout {
    address pairImplementation;
    address poolImplementation;
  }

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }
}
