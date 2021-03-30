// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';

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
   * @notice calculate or get cached volatility for current day
   * @return volatility
   */
  function getVolatility () external view returns (uint) {
    PairStorage.Layout storage l = PairStorage.layout();
    return uint(l.emavariance);
  }

  /**
   * @notice updates state variables
   */
  function update() internal {
    PairStorage.Layout storage l = PairStorage.layout();
    require(l.lasttimestamp + l.period < block.timestamp, "Wait to update");

    l.lasttimestamp = block.timestamp;
    (l.priceYesterday64x64, l.priceToday64x64) = (l.priceToday64x64, l.IPrice.getLatestPrice(l.oracle));
    l.logreturns = OptionMath.logreturns(l.priceToday64x64, l.priceYesterday64x64);
    (l.emalogreturns_yesterday, l.emalogreturns_today) = (l.emalogreturns_today, OptionMath.rollingEma(l.emalogreturns_yesterday, l.logreturns, l.window));
    l.emavariance = OptionMath.rollingEmaVar(l.logreturns, l.emalogreturns_yesterday, l.emavariance, l.window);
  }
}
