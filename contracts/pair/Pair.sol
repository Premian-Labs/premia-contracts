// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/contracts/access/OwnableInternal.sol';

import './PairStorage.sol';

/**
 * @title Openhedge options pair
 * @dev deployed standalone and referenced by PairProxy
 */
contract Pair is OwnableInternal {
  /**
   * @notice calculate or get cached volatility for current day
   * @return volatility
   */
  function getVolatility () external view returns (uint) {
    uint day = block.timestamp / (1 days);

    PairStorage.Layout storage l = PairStorage.layout();

    if (l.volatilityByDay[day] == 0) {
      // TODO: calculate volatility for today
    }

    return l.volatilityByDay[day];
  }
}
