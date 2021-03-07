// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';

import './PairStorage.sol';

import { OptionMath } from '../libraries/OptionMath.sol';

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
    PairStorage.Layout storage l = PairStorage.layout();
    return uint(l.variance);
  }

  /**
   * @notice updates state variables
   */
  function update() internal {
    PairStorage.Layout storage l = PairStorage.layout();
    require(l.lasttimestamp + l.period < block.timestamp, "Wait to update");
    l.lasttimestamp = block.timestamp;
    (l.priceyesterday, l.pricetoday) = (l.pricetoday, l.IPrice.getLatestPrice(l.oracle));
    l.logreturns = OptionMath.logreturns(l.pricetoday, l.priceyesterday);
    (l.emalogreturns_yesterday, l.emalogreturns_today) = (l.emalogreturns_today, OptionMath.rollingEma(l.emalogreturns_yesterday, l.logreturns, l.window));
    (l.averageyesterday, l.averagetoday) = (l.averagetoday, OptionMath.rollingAvg(l.averageyesterday, l.emalogreturns_today, l.window));
    l.variance = OptionMath.rollingVar(l.emalogreturns_yesterday, l.emalogreturns_today, l.averageyesterday, l.averagetoday, l.variance, l.window);
  }
}
