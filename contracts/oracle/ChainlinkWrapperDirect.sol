// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @notice Used as a replacement of ChainlinkWrapper, to use a Chainlink price feed deployed afterwards
contract ChainlinkWrapperDirect {
    address internal immutable CHAINLINK_PRICE_FEED;

    constructor(address chainlinkPriceFeed) {
        CHAINLINK_PRICE_FEED = chainlinkPriceFeed;
    }

    function latestAnswer() external view returns (int256) {
        return AggregatorInterface(CHAINLINK_PRICE_FEED).latestAnswer();
    }

    function decimals() external view returns (uint8) {
        return AggregatorV3Interface(CHAINLINK_PRICE_FEED).decimals();
    }
}
