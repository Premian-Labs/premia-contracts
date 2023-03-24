// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IChainlinkWrapperInternal {
    /// @notice Thrown when attempting to increase array size
    error ChainlinkWrapper__ArrayCannotExpand();

    /// @notice Thrown when cardinality per minute has not been set
    error ChainlinkWrapper__CardinalityPerMinuteNotSet();

    /// @notice Thrown when trying to add an existing fee tier
    error ChainlinkWrapper__FeeTierExists(uint24 feeTier);

    /// @notice Thrown when trying to add an invalid fee tier
    error ChainlinkWrapper__InvalidFeeTier(uint24 feeTier);

    /// @notice Thrown when the lastRoundData call reverts without a reason
    error ChainlinkWrapper__LatestRoundDataCallReverted(bytes data);

    /// @notice Thrown when the price is non-positive
    error ChainlinkWrapper__NonPositivePrice(int256 price);

    /// @notice Thrown when current observation cardinality is below target cardinality
    error ChainlinkWrapper__ObservationCardinalityTooLow();

    /// @notice Thrown when period has not been set
    error ChainlinkWrapper__PeriodNotSet();

    /// @notice Emitted when a new period is set
    /// @param period The new period
    event UpdatedPeriod(uint32 period);

    /// @notice Emitted when a new cardinality per minute is set
    /// @param cardinalityPerMinute The new cardinality per minute
    event UpdatedCardinalityPerMinute(uint8 cardinalityPerMinute);
}
