// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IChainlinkWrapperInternal} from "./IChainlinkWrapperInternal.sol";

/// @notice Used as a replacement of ChainlinkWrapper, to use a Chainlink price feed deployed afterwards
contract ChainlinkWrapperDirect is IChainlinkWrapperInternal {
    AggregatorV3Interface internal immutable CHAINLINK_PRICE_FEED;

    constructor(address chainlinkPriceFeed) {
        CHAINLINK_PRICE_FEED = AggregatorV3Interface(chainlinkPriceFeed);
    }

    function latestAnswer() external view returns (int256) {
        try CHAINLINK_PRICE_FEED.latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        ) {
            return answer;
        } catch Error(string memory reason) {
            revert(reason);
        } catch (bytes memory data) {
            revert ChainlinkWrapper__LatestRoundDataCallReverted(data);
        }
    }

    function decimals() external view returns (uint8) {
        return CHAINLINK_PRICE_FEED.decimals();
    }
}
