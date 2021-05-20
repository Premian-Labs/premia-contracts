// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library ProxyManagerStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'premia.contracts.storage.ProxyManager'
  );

  struct Layout {
    address optionImplementation;
    address marketImplementation;
    address optionProxy;
    address marketProxy;
  }

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }
}
