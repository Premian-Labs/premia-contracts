// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import {ERC1155EnumerableStorage} from '@solidstate/contracts/token/ERC1155/ERC1155EnumerableStorage.sol';

import {ABDKMath64x64} from 'abdk-libraries-solidity/ABDKMath64x64.sol';
import {ABDKMath64x64Token} from '../libraries/ABDKMath64x64Token.sol';
import {OptionMath} from '../libraries/OptionMath.sol';
import {Pool} from './Pool.sol';

library PoolStorage {
  enum TokenType { UNDERLYING_FREE_LIQ, BASE_FREE_LIQ, LONG_CALL, SHORT_CALL, LONG_PUT, SHORT_PUT }

  bytes32 internal constant STORAGE_SLOT = keccak256(
    'premia.contracts.storage.Pool'
  );

  struct Layout {
    // Base token
    address base;
    // Underlying token
    address underlying;

    address baseOracle;
    address underlyingOracle;

    uint8 underlyingDecimals;
    uint8 baseDecimals;

    int128 cLevelUnderlying64x64;
    int128 cLevelBase64x64;

    int128 fee64x64;

    uint256 updatedAt;
    int128 emaLogReturns64x64;
    int128 emaVarianceAnnualized64x64;

    mapping (address => uint256) underlyingDepositedAt;
    mapping (address => uint256) baseDepositedAt;

    // doubly linked list of free liquidity intervals
    mapping (address => address) underlyingLiquidityQueueAscending;
    mapping (address => address) underlyingLiquidityQueueDescending;

    mapping (address => address) baseLiquidityQueueAscending;
    mapping (address => address) baseLiquidityQueueDescending;

    // TODO: enforced interval size for maturity (maturity % interval == 0)
    // updatable by owner

    // minimum resolution price bucket => price
    mapping (uint256 => int128) bucketPrices64x64;
    // sequence id (minimum resolution price bucket / 256) => price update sequence
    mapping (uint256 => uint256) priceUpdateSequences;
  }

  ////////////////////////////////////////////
  ////////////////////////////////////////////
  // To avoid stack too deep error

  struct QuoteArgs {
    uint64 maturity; // timestamp of option maturity
    int128 strike64x64; // 64x64 fixed point representation of strike price
    int128 spot64x64; // 64x64 fixed point representation of spot price
    uint256 amount; // size of option contract
    bool isCall; // true for call, false for put
  }

  struct PurchaseArgs {
    uint64 maturity; // timestamp of option maturity
    int128 strike64x64; // 64x64 fixed point representation of strike price
    uint256 amount; // size of option contract
    uint256 maxCost; // maximum acceptable cost after accounting for slippage
    bool isCall; // true for call, false for put
  }

  struct ExerciseArgs {
    uint256 longTokenId; // amount quantity of option contract tokens to exercise
    uint256 amount; // quantity of option contract tokens to exercise
    bool isCall; // true for call, false for put
  }

  ////////////////////////////////////////////
  ////////////////////////////////////////////

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }

  /**
   * @notice calculate ERC1155 token id for given option parameters
   * @param tokenType TokenType enum
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @return tokenId token id
   */
  function formatTokenId (
    TokenType tokenType,
    uint64 maturity,
    int128 strike64x64
  ) internal pure returns (uint256 tokenId) {
    // TODO: fix probably Hardhat issue related to usage of assembly
    // assembly {
    //   tokenId := add(shl(248, tokenType), add(shl(128, maturity), strike64x64))
    // }

    tokenId = (uint256(tokenType) << 248) + (uint256(maturity) << 128) + uint256(int256(strike64x64));
  }

  /**
   * @notice derive option maturity and strike price from ERC1155 token id
   * @param tokenId token id
   * @return tokenType TokenType enum
   * @return maturity timestamp of option maturity
   * @return strike64x64 option strike price
   */
  function parseTokenId (
    uint256 tokenId
  ) internal pure returns (TokenType tokenType, uint64 maturity, int128 strike64x64) {
    assembly {
      tokenType := shr(248, tokenId)
      maturity := shr(128, tokenId)
      strike64x64 := tokenId
    }
  }

  function totalSupply64x64 (
    Layout storage l,
    uint256 tokenId
  ) internal view returns (int128) {
    return ABDKMath64x64Token.fromDecimals(
      ERC1155EnumerableStorage.layout().totalSupply[tokenId], l.underlyingDecimals
    );
  }

  function addUnderwriter (
    Layout storage l,
    address account,
    bool isCallPool
  ) internal {
    if (isCallPool) {
      l.underlyingLiquidityQueueAscending[l.underlyingLiquidityQueueDescending[address(0)]] = account;
      l.underlyingLiquidityQueueDescending[address(0)] = account;
    } else {
      l.baseLiquidityQueueAscending[l.baseLiquidityQueueDescending[address(0)]] = account;
      l.baseLiquidityQueueDescending[address(0)] = account;
    }
  }

  function removeUnderwriter (
    Layout storage l,
    address account,
    bool isCallPool
  ) internal {
    if (isCallPool) {
      address prev = l.underlyingLiquidityQueueDescending[account];
      address next = l.underlyingLiquidityQueueAscending[account];
      l.underlyingLiquidityQueueAscending[prev] = next;
      l.underlyingLiquidityQueueDescending[next] = prev;
      delete l.underlyingLiquidityQueueAscending[account];
      delete l.underlyingLiquidityQueueDescending[account];
    } else {
      address prev = l.baseLiquidityQueueDescending[account];
      address next = l.baseLiquidityQueueAscending[account];
      l.baseLiquidityQueueAscending[prev] = next;
      l.baseLiquidityQueueDescending[next] = prev;
      delete l.baseLiquidityQueueAscending[account];
      delete l.baseLiquidityQueueDescending[account];
    }
  }

  function getCLevel (
    Layout storage l,
    bool isCall
  ) internal view returns (int128 cLevel64x64) {
    cLevel64x64 = isCall ? l.cLevelUnderlying64x64 : l.cLevelBase64x64;
  }

  function setCLevel (
    Layout storage l,
    int128 oldLiquidity64x64,
    int128 newLiquidity64x64,
    bool isCallPool
  ) internal {
    if (isCallPool) {
      l.cLevelUnderlying64x64 = OptionMath.calculateCLevel(
        l.cLevelUnderlying64x64,
        oldLiquidity64x64,
        newLiquidity64x64,
        OptionMath.ONE_64x64
      );
    } else {
      l.cLevelBase64x64 = OptionMath.calculateCLevel(
        l.cLevelBase64x64,
        oldLiquidity64x64,
        newLiquidity64x64,
        OptionMath.ONE_64x64
      );
    }
  }

  function setCLevel (
    Layout storage l,
    int128 cLevel64x64,
    bool isCallPool
  ) internal {
    if (isCallPool) {
      l.cLevelUnderlying64x64 = cLevel64x64;
    } else {
      l.cLevelBase64x64 = cLevel64x64;
    }
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

  function fetchPriceUpdate (
    Layout storage l
  ) internal returns (int128 price64x64) {
    (, int256 priceUnderlying, , ,) = AggregatorV3Interface(l.underlyingOracle).latestRoundData();
    (, int256 priceBase, , ,) = AggregatorV3Interface(l.baseOracle).latestRoundData();

    return ABDKMath64x64.divi(
      priceUnderlying,
      priceBase
    );
  }

  function setPriceUpdate (
    Layout storage l,
    int128 price64x64
  ) internal {
    // TODO: check for off-by-one errors
    uint bucket = block.timestamp / (1 hours);
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
