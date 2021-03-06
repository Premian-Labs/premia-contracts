// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';

import './PairStorage.sol';

/**
 * @title Openhedge options pair
 * @dev deployed standalone and referenced by PairProxy
 */
contract Pair is OwnableInternal {
  using PairStorage for PairStorage.Layout;

  /**
   * @notice get addresses of PoolProxy contracts
   * @return pool addresses
   */
  function getPools () external view returns (address, address) {
    return PairStorage.layout().getPools();
  }

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

  /**
   * @notice updates state variables
   */
  function update() internal {
    PairStorage.Layout storage l = PairStorage.layout();
    require(l.lasttimestamp + l.period < block.timestamp, "Wait to update");
    // TODO: use option math to update storage variables
    l.lasttimestamp = block.timestamp;
    l.oldprice = l.lastprice;

  }
}
