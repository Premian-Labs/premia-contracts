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

    // TODO: enforced interval size for maturity (maturity % interval == 0)
    // updatable by owner

    // minimum resolution price bucket => price
    mapping (uint256 => int128) bucketPrices64x64;
    // sequence id (minimum resolution price bucket / 256) => price update sequence
    mapping (uint256 => uint256) priceUpdateSequences;
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

  function setPriceUpdate (
    Layout storage l,
    uint timestamp,
    int128 price64x64
  ) internal {
    // TODO: check for off-by-one errors
    uint bucket = timestamp / (1 hours);
    l.bucketPrices64x64[bucket] = price64x64;
    l.priceUpdateSequences[bucket >> 8] += 1 << 256 - (bucket & 255);
  }

  function getPriceUpdate (
    Layout storage l,
    uint timestamp
  ) internal view returns (int128) {
    return l.bucketPrices64x64[timestamp / (1 hours)];
  }

  function getPriceUpdateAfter (
    Layout storage l,
    uint timestamp
  ) internal view returns (int128) {
    // TODO: check for off-by-one errors
    uint bucket = timestamp / (1 hours);
    uint sequenceId = bucket >> 8;
    // shift to skip buckets from earlier in sequence
    uint offset = bucket & 255;
    uint sequence = l.priceUpdateSequences[sequenceId] << offset >> offset;

    uint currentPriceUpdateSequenceId = block.timestamp / (256 hours);

    while (sequence == 0 && sequenceId <= currentPriceUpdateSequenceId) {
      sequence = l.priceUpdateSequences[++sequenceId];
    }

    if (sequence == 0) {
      // TODO: no price update found; continuing function will return 0 anyway
      return 0;
    }

    uint256 msb; // most significant bit

    for (uint256 i = 128; i > 0; i >> 1) {
      if (sequence >> i > 0) {
        msb += i;
        sequence >>= i;
      }
    }

    return l.bucketPrices64x64[(sequenceId + 1 << 8) - msb];
  }
}
