// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';

import '../core/IPriceConsumer.sol';
import './IPair.sol';
import './PairStorage.sol';

import { OptionMath } from '../libraries/OptionMath.sol';

/**
 * @title Median options pair
 * @dev deployed standalone and referenced by PairProxy
 */
contract Pair is IPair, OwnableInternal {
  using PairStorage for PairStorage.Layout;

  /**
   * @notice get addresses of PoolProxy contracts
   * @return pool addresses
   */
  function getPools () external view returns (address, address) {
    return PairStorage.layout().getPools();
  }

  /**
   * @inheritdoc IPair
   */
  function getVariance () external override view returns (int128 variance64x64) {
    // TODO: calculate
    variance64x64 = PairStorage.layout().emaVarianceAnnualized64x64;
  }

 /**
   * @notice updates state variables
   */
  function update() internal {
    PairStorage.Layout storage l = PairStorage.layout();

    // TODO: skip if trivial amount of time has passed since last update
    if (l.lasttimestamp + l.period >= block.timestamp) return;

    uint today = block.timestamp / 86400;
    uint lastDay = l.lasttimestamp / 86400;
    (roundId, newPrice64x64) = IPriceConsumer(OwnableStorage.layout().owner).getLatestPrice(l.oracle);

    // TODO: skip if retrieved round ID is same as last round ID
    if(l.dayToRoundId[lastDay] == roundId) return;

    l.dayToRoundId[today] = roundId;
    
    if(today == lastDay){
      l.dayToClosingPrice64x64[today] = newPrice64x64;
    } else {
      l.dayToOpeningPrice64x64[today] = newPrice64x64;
      // TODO: perform binary search to find and store actual close (both price and roundId)

      int128 logreturns64x64 = OptionMath.logreturns(l.dayToClosingPrice64x64[today], l.dayToClosingPrice64x64[lastDay]);

      (
        l.oldEmaLogReturns64x64,
        l.newEmaLogReturns64x64
      ) = (
        l.newEmaLogReturns64x64,
        OptionMath.rollingEma(l.oldEmaLogReturns64x64, logreturns64x64, l.window)
      );

      l.emaVarianceAnnualized64x64 = OptionMath.rollingEmaVariance(
        l.emaVarianceAnnualized64x64 / 365,
        l.oldEmaLogReturns64x64,
        logreturns64x64,
        l.window
      ) * 365;
    }
  }
}
