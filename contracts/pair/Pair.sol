// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import '@solidstate/contracts/access/OwnableInternal.sol';

import './IPair.sol';
import './PairStorage.sol';

import { OptionMath } from '../libraries/OptionMath.sol';
import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';

/**
 * @title Median options pair
 * @dev deployed standalone and referenced by PairProxy
 */
contract Pair is IPair, OwnableInternal {
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
   * @inheritdoc IPair
   */
  function getVariance () external override view returns (int128 variance64x64) {
    // TODO: calculate
    variance64x64 = PairStorage.layout().emaVarianceAnnualized64x64;
  }

  /**
   * @notice fetch latest price from given oracle
   * @param oracle Chainlink price aggregator address
   * @return price latest price
   */
  function _fetchLatestPrice (
    address oracle
  ) internal view returns (int256 price) {
    (, price, , ,) = AggregatorV3Interface(oracle).latestRoundData();
  }

  /**
   * @notice TODO
   */
  function _update () internal {
    PairStorage.Layout storage l = PairStorage.layout();

    // TODO: skip if trivial amount of time has passed since last update
    if (block.timestamp <= l.updatedAt + 1 hours) return;

    int128 price64x64 = ABDKMath64x64.divi(
      _fetchLatestPrice(l.oracle0),
      _fetchLatestPrice(l.oracle1)
    );

    l.updatedAt = block.timestamp;

    // TODO: update time-weighted EMA
    //
    // int128 logreturns64x64 = OptionMath.logreturns(l.dayToClosingPrice64x64[today], l.dayToClosingPrice64x64[lastDay]);
    //
    // (
    //   l.oldEmaLogReturns64x64,
    //   l.newEmaLogReturns64x64
    // ) = (
    //   l.newEmaLogReturns64x64,
    //   OptionMath.rollingEma(l.oldEmaLogReturns64x64, logreturns64x64, l.window)
    // );
    //
    // l.emaVarianceAnnualized64x64 = OptionMath.rollingEmaVariance(
    //   l.emaVarianceAnnualized64x64 / 365,
    //   l.oldEmaLogReturns64x64,
    //   logreturns64x64,
    //   l.window
    // ) * 365;
  }
}
