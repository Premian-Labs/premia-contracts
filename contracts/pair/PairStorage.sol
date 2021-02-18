// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library PairStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'openhedge.contracts.storage.Pair'
  );

  struct Layout {
    mapping (uint => uint) volatilityByDay;
  }

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }
}
