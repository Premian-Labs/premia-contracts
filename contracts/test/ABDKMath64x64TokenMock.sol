// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ABDKMath64x64Token } from '../libraries/ABDKMath64x64Token.sol';

contract ABDKMath64x64TokenMock {
  function toDecimals (
    int128 value64x64,
    uint8 decimals
  ) external pure returns (uint256) {
    return ABDKMath64x64Token.toDecimals(value64x64, decimals);
  }

  function fromDecimals (
    uint256 value,
    uint8 decimals
  ) external pure returns (int128) {
    return ABDKMath64x64Token.fromDecimals(value, decimals);
  }

  function toWei (
    int128 value64x64
  ) external pure returns (uint256) {
    return ABDKMath64x64Token.toWei(value64x64);
  }

  function fromWei (
    uint256 value
  ) external pure returns (int128) {
    return ABDKMath64x64Token.fromWei(value);
  }
}
