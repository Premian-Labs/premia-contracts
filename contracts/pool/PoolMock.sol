// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import './Pool.sol';

contract PoolMock is Pool {
  function tokenIdFor (
    uint192 strikePrice,
    uint64 maturity
  ) external view returns (uint) {
    return _tokenIdFor(strikePrice, maturity);
  }
}
