// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol';

import './IPriceConsumer.sol';

/**
 * @title Chainlink price feed contract
 * @dev deployed standalone and connected to Median as diamond facet
 */
contract PriceConsumer is IPriceConsumer {
  // TODO: no storage variables outside of diamond storage layout
  AggregatorV3Interface internal priceFeed;

  function getLatestPrice(address _feed) override public view returns (int) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_feed).latestRoundData();
        return price;
    }
}
