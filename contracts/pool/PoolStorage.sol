// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorInterface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol';
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

    uint256 updatedAt;
    int128 emaLogReturns64x64;
    int128 emaVarianceAnnualized64x64;

    // User -> isCall -> depositedAt
    mapping (address => mapping(bool => uint256)) depositedAt;

    // doubly linked list of free liquidity intervals
    // User -> isCall -> User
    mapping (address => mapping(bool => address)) liquidityQueueAscending;
    mapping (address => mapping(bool => address)) liquidityQueueDescending;

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

  struct PoolSettings {
    address underlying;
    address base;
    address underlyingOracle;
    address baseOracle;
  }

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
    (TokenType tokenType,,) = parseTokenId(tokenId);
    return ABDKMath64x64Token.fromDecimals(
      ERC1155EnumerableStorage.layout().totalSupply[tokenId],
      tokenType == TokenType.BASE_FREE_LIQ ? l.baseDecimals : l.underlyingDecimals
    );
  }

  function addUnderwriter (
    Layout storage l,
    address account,
    bool isCallPool
  ) internal {
    l.liquidityQueueAscending[l.liquidityQueueDescending[address(0)][isCallPool]][isCallPool] = account;
    l.liquidityQueueDescending[address(0)][isCallPool] = account;
  }

  function removeUnderwriter (
    Layout storage l,
    address account,
    bool isCallPool
  ) internal {
    address prev = l.liquidityQueueDescending[account][isCallPool];
    address next = l.liquidityQueueAscending[account][isCallPool];
    l.liquidityQueueAscending[prev][isCallPool] = next;
    l.liquidityQueueDescending[next][isCallPool] = prev;
    delete l.liquidityQueueAscending[account][isCallPool];
    delete l.liquidityQueueDescending[account][isCallPool];
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
  ) internal view returns (int128 price64x64) {
    int256 priceUnderlying = AggregatorInterface(l.underlyingOracle).latestAnswer();
    int256 priceBase = AggregatorInterface(l.baseOracle).latestAnswer();

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
    // TODO: underflow
    uint offset = (bucket & 255) - 1;
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

    if (sequence >= 2**128) {
        sequence >>= 128;
        msb += 128;
    }
    if (sequence >= 2**64) {
        sequence >>= 64;
        msb += 64;
    }
    if (sequence >= 2**32) {
        sequence >>= 32;
        msb += 32;
    }
    if (sequence >= 2**16) {
        sequence >>= 16;
        msb += 16;
    }
    if (sequence >= 2**8) {
        sequence >>= 8;
        msb += 8;
    }
    if (sequence >= 2**4) {
        sequence >>= 4;
        msb += 4;
    }
    if (sequence >= 2**2) {
        sequence >>= 2;
        msb += 2;
    }
    if (sequence >= 2**1) {
        // No need to shift x any more.
        msb += 1;
    }

    return l.bucketPrices64x64[(sequenceId + 1 << 8) - msb];
  }

  function fromBaseToUnderlyingDecimals (
    Layout storage l,
    uint256 value
  ) internal view returns (uint256) {
    int128 valueFixed64x64 = ABDKMath64x64Token.fromDecimals(value, l.baseDecimals);
    return ABDKMath64x64Token.toDecimals(valueFixed64x64, l.underlyingDecimals);
  }

  function fromUnderlyingToBaseDecimals (
    Layout storage l,
    uint256 value
  ) internal view returns (uint256) {
    int128 valueFixed64x64 = ABDKMath64x64Token.fromDecimals(value, l.underlyingDecimals);
    return ABDKMath64x64Token.toDecimals(valueFixed64x64, l.baseDecimals);
  }
}
