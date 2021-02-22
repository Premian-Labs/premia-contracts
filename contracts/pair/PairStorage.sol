// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library PairStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'openhedge.contracts.storage.Pair'
  );

  struct Layout {
    address pool0;
    address pool1;
    mapping (uint => uint) volatilityByDay;
  }

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }

  function getPools (
    Layout storage l
  ) internal view returns (address, address) {
    return (l.pool0, l.pool1);
  }

  function setPools (
    Layout storage l,
    address pool0,
    address pool1
  ) internal {
    l.pool0 = pool0;
    l.pool1 = pool1;
  }
}
