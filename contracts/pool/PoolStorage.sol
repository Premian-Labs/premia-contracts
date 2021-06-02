// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/token/ERC20/ERC20BaseStorage.sol';

import { ABDKMath64x64Token } from '../libraries/ABDKMath64x64Token.sol';
import { OptionMath } from '../libraries/OptionMath.sol';

library PoolStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'premia.contracts.storage.Pool'
  );

  struct Layout {
    address treasury;
    address pair;
    address underlying;
    uint8 underlyingDecimals;
    int128 cLevel64x64;
    int128 fee64x64;

    mapping (address => uint256) depositedAt;

    mapping (address => uint256) divestmentTimestamps;

    // doubly linked list of free liquidity intervals
    mapping (address => address) liquidityQueueAscending;
    mapping (address => address) liquidityQueueDescending;
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

  function getReinvestmentStatus (
    Layout storage l,
    address account
  ) internal view returns (bool) {
    uint256 timestamp = l.divestmentTimestamps[account];
    return timestamp == 0 || timestamp > block.timestamp;
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
}
