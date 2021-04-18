// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

library PairStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'median.contracts.storage.Pair'
  );

  struct Layout {
    // TODO: ordering of assets (and oracles and pools)
    address asset0;
    address asset1;
    address oracle0;
    address oracle1;
    address pool0;
    address pool1;

    uint256 updatedAt;

    int128 emaVarianceAnnualized64x64;
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

  function setOracles(
    Layout storage l,
    address oracle0,
    address oracle1
  ) internal {
    require(
      AggregatorV3Interface(oracle0).decimals() == AggregatorV3Interface(oracle1).decimals(),
      'Pair: oracle decimals must match'
    );

    l.oracle0 = oracle0;
    l.oracle1 = oracle1;
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
