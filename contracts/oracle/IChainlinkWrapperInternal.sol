// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IChainlinkWrapperInternal {
    /// @notice Thrown when attempting to increase array size
    error ChainlinkWrapper__ArrayCannotExpand();

    /// @notice Thrown when trying to add an existing fee tier
    error ChainlinkWrapper__FeeTierExists(uint24 feeTier);

    /// @notice Thrown when trying to add an invalid fee tier
    error ChainlinkWrapper__InvalidFeeTier(uint24 feeTier);

    /// @notice Thrown when the lastRoundData call reverts without a reason
    error ChainlinkWrapper__LatestRoundDataCallReverted(bytes data);

    /// @notice Thrown when the price is non-positive
    error ChainlinkWrapper__NonPositivePrice(int256 price);
}
