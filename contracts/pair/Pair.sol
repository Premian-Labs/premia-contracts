// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';

import '../core/IPriceConsumer.sol';
import './PairStorage.sol';

import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';
import { OptionMath } from '../libraries/OptionMath.sol';

/**
 * @title Median options pair
 * @dev deployed standalone and referenced by PairProxy
 */
contract Pair is OwnableInternal {
  using ABDKMath64x64 for int128;
  using PairStorage for PairStorage.Layout;

  /**
   * @notice get addresses of PoolProxy contracts
   * @return pool addresses
   */
  function getPools () external view returns (address, address) {
    return PairStorage.layout().getPools();
  }

  /**
   * @notice calculate or get cached variance for current day
   * @return variance
   */
  function getVariance () external view returns (int128) {
    // TODO: calculate
    return PairStorage.layout().emaVarianceAnnualized64x64;
  }

  /**
   * @notice updates state variables
   */
  function update() internal {
    PairStorage.Layout storage l = PairStorage.layout();

    // TODO: skip if trivial amount of time has passed since last update
    // TODO: skip if retrieved round ID is same as last round ID

    (
      l.oldPrice64x64,
      l.newPrice64x64
    ) = (
      l.newPrice64x64,
      IPriceConsumer(OwnableStorage.layout().owner).getLatestPrice(l.oracle)
    );

    int128 logReturns64x64 = l.newPrice64x64.div(l.oldPrice64x64).ln();

    (
      l.oldEmaLogReturns64x64,
      l.newEmaLogReturns64x64
    ) = (
      l.newEmaLogReturns64x64,
      OptionMath.rollingEma(l.oldEmaLogReturns64x64, logReturns64x64, l.window)
    );

    l.emaVarianceAnnualized64x64 = OptionMath.rollingEmaVariance(
      l.emaVarianceAnnualized64x64 / 365,
      l.oldEmaLogReturns64x64,
      logReturns64x64,
      l.window
    ) * 365;
  }
}
