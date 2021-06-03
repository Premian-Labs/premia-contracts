// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import {OwnableInternal} from '@solidstate/contracts/access/OwnableInternal.sol';

import {IPair} from './IPair.sol';
import {PairStorage} from './PairStorage.sol';

import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';
import { OptionMath } from '../libraries/OptionMath.sol';

/**
 * @title Premia options pair
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
   * TODO: define base and underlying
   * @inheritdoc IPair
   */
  function updateAndGetLatestData () override external returns (int128 price64x64, int128 variance64x64) {
    _update();
    PairStorage.Layout storage l = PairStorage.layout();
    price64x64 = l.getPriceUpdate(block.timestamp);
    variance64x64 = l.emaVarianceAnnualized64x64;
  }

  /**
   * TODO: define base and underlying
   * @inheritdoc IPair
   */
  function updateAndGetHistoricalPrice (
    uint256 timestamp
  ) override external returns (int128 price64x64) {
    _update();
    price64x64 = PairStorage.layout().getPriceUpdateAfter(timestamp);
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

    uint256 updatedAt = l.updatedAt;

    int128 oldPrice64x64 = l.getPriceUpdate(updatedAt);
    int128 newPrice64x64 = ABDKMath64x64.divi(
      _fetchLatestPrice(l.oracle0),
      _fetchLatestPrice(l.oracle1)
    );

    if (l.getPriceUpdate(block.timestamp) == 0) {
      l.setPriceUpdate(block.timestamp, newPrice64x64);
    }

    int128 logReturns64x64 = newPrice64x64.div(oldPrice64x64).ln();
    int128 oldEmaLogReturns64x64 = l.emaLogReturns64x64;

    l.emaLogReturns64x64 = OptionMath.unevenRollingEma(
      oldEmaLogReturns64x64,
      logReturns64x64,
      updatedAt,
      block.timestamp
    );

    l.emaVarianceAnnualized64x64 = OptionMath.unevenRollingEmaVariance(
      oldEmaLogReturns64x64,
      l.emaVarianceAnnualized64x64 / 365,
      logReturns64x64,
      updatedAt,
      block.timestamp
    ) * 365;

    l.updatedAt = block.timestamp;
  }
}
