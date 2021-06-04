// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

import {ERC20BaseStorage} from '@solidstate/contracts/token/ERC20/ERC20BaseStorage.sol';

import { ABDKMath64x64Token } from '../libraries/ABDKMath64x64Token.sol';
import { OptionMath } from '../libraries/OptionMath.sol';

library PoolStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'premia.contracts.storage.Pool'
  );

  struct Layout {
    address treasury;

    // Base token
    address base;
    // Underlying token
    address underlying;

    address baseOracle;
    address underlyingOracle;

    uint8 underlyingDecimals;
    int128 cLevel64x64;
    int128 fee64x64;

    uint256 updatedAt;

    int128 emaLogReturns64x64;
    int128 emaVarianceAnnualized64x64;

    mapping (address => uint256) depositedAt;

    // doubly linked list of free liquidity intervals
    mapping (address => address) liquidityQueueAscending;
    mapping (address => address) liquidityQueueDescending;

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

  function totalSupply64x64 (
    Layout storage l
  ) internal view returns (int128) {
    return ABDKMath64x64Token.fromDecimals(
      ERC20BaseStorage.layout().totalSupply, l.underlyingDecimals
    );
  }

  function addUnderwriter (
    Layout storage l,
    address account
  ) internal {
    l.liquidityQueueAscending[l.liquidityQueueDescending[address(0)]] = account;
  }

  function removeUnderwriter (
    Layout storage l,
    address account
  ) internal {
    address prev = l.liquidityQueueDescending[account];
    address next = l.liquidityQueueAscending[account];
    l.liquidityQueueAscending[prev] = next;
    l.liquidityQueueDescending[next] = prev;
    delete l.liquidityQueueAscending[account];
    delete l.liquidityQueueDescending[account];
  }

  function setCLevel (
    Layout storage l,
    int128 oldLiquidity64x64,
    int128 newLiquidity64x64
  ) internal {
    l.cLevel64x64 = OptionMath.calculateCLevel(
      l.cLevel64x64,
      oldLiquidity64x64,
      newLiquidity64x64,
      OptionMath.ONE_64x64
    );
  }

  function setOracles(
    Layout storage l,
    address baseOracle,
    address underlyingOracle
  ) internal {
    require(
      AggregatorV3Interface(baseOracle).decimals() == AggregatorV3Interface(underlyingOracle).decimals(),
      'Pool: oracle decimals must match'
    );

    l.baseOracle = baseOracle;
    l.underlyingOracle = underlyingOracle;
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
