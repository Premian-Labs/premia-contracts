// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol';
import {ABDKMath64x64} from 'abdk-libraries-solidity/ABDKMath64x64.sol';

import './IPriceConsumer.sol';

/**
 * @title Chainlink price feed contract
 * @dev deployed standalone and connected to Median as diamond facet
 */
contract PriceConsumer is IPriceConsumer {
  // TODO: no storage variables outside of diamond storage layout
  AggregatorV3Interface internal priceFeed;

  function getLatestPrice(address _feed) override public view returns (int128) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_feed).latestRoundData();

        // TODO: convert received price to 64x64 fixed-point representation
        return ABDKMath64x64.fromInt(price);
    }
}
