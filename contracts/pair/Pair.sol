// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';

import '../core/IPriceConsumer.sol';
import './PairStorage.sol';

import { OptionMath } from '../libraries/OptionMath.sol';

/**
 * @title Median options pair
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
   * @notice calculate or get cached variance for current day
   * @return variance
   */
  function getVariance () external view returns (int128) {
    // TODO: calculate
    return PairStorage.layout().emavariance;
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

    int128 logreturns64x64 = OptionMath.logreturns(l.newPrice64x64, l.oldPrice64x64);

    (
      l.oldEmaLogReturns64x64,
      l.newEmaLogReturns64x64
    ) = (
      l.newEmaLogReturns64x64,
      OptionMath.rollingEma(l.oldEmaLogReturns64x64, logreturns64x64, l.window)
    );

    l.emavariance = OptionMath.rollingEmaVariance(
      logreturns64x64,
      l.oldEmaLogReturns64x64,
      l.emavariance,
      l.window
    );
  }
}
