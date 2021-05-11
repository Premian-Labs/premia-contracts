// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPair {
  /**
   * @notice update cache and get most recent price and variance
   * @return price64x64 64x64 fixed point representation of price
   * @return variance64x64 64x64 fixed point representation of EMA of annualized variance
   */
  function updateAndGetLatestData () external returns (int128 price64x64, int128 variance64x64);

  /**
   * @notice update cache and get price for given timestamp
   * @param timestamp timestamp of price to query
   * @return price64x64 64x64 fixed point representation of price
   */
  function updateAndGetHistoricalPrice (
    uint256 timestamp
  ) external returns (int128 price64x64);
}
