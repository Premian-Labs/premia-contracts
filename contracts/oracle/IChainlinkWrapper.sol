// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {IUniswapV3Factory} from "../vendor/uniswap/IUniswapV3Factory.sol";

interface IChainlinkWrapper {
    /// @notice Returns the zero address
    /// @return The zero address
    function aggregator() external view returns (address);

    /// @notice Returns the decimal places of the price
    /// @return The decimal places of the price
    function decimals() external view returns (uint8);

    /// @notice Returns the USD price of a Uniswap pair (tokenIn/tokenOut) using the tokenOut/USD Chainlink oracle
    /// @return The USD price of the pair
    function latestAnswer() external view returns (int256);

    /// @notice Returns the address of the Uniswap V3 factory
    /// @dev This value is assigned during deployment and cannot be changed
    /// @return The address of the Uniswap V3 factory
    function factory() external view returns (IUniswapV3Factory);

    /// @notice Returns the address of the tokenOut/USD Chainlink oracle
    /// @dev This value is assigned during deployment and cannot be changed
    /// @return The address of the tokenOut/USD Chainlink oracle
    function oracle() external view returns (AggregatorV3Interface);

    /// @notice Returns the address of the Uniswap pair (tokenIn/tokenOut)
    /// @dev This value is assigned during deployment and cannot be changed
    /// @return The address of the Uniswap pair (tokenIn/tokenOut)
    function pair() external view returns (address, address);

    /// @notice Returns the period used for the TWAP calculation
    /// @return The period used for the TWAP
    function period() external view returns (uint32);

    /// @notice Returns the cardinality per minute used for adding support to pairs
    /// @return The cardinality per minute used for increase cardinality calculations
    function cardinalityPerMinute() external view returns (uint8);

    /// @notice Returns the target observation cardinality for pools
    /// @return The target observation cardinality for pools
    function targetCardinality() external view returns (uint16);

    /// @notice Returns all supported fee tiers
    /// @return The supported fee tiers
    function supportedFeeTiers() external view returns (uint24[] memory);

    /// @notice Sets the period to be used for the TWAP calculation
    /// @dev Will revert it is lower than the minimum period or greater than maximum period.
    ///      Can only be called by owner
    ///      WARNING: increasing the period could cause big problems, because Uniswap V3 pools might not support a TWAP so old
    /// @param newPeriod The new period
    function setPeriod(uint32 newPeriod) external;

    /// @notice Sets the cardinality per minute to be used when increasing observation cardinality at the moment of adding support for pairs
    /// @dev Will revert if the given cardinality is zero
    ///      Can only be called by users with the admin role
    ///      WARNING: increasing the cardinality per minute will make adding support to a pair significantly costly
    /// @param cardinalityPerMinute The new cardinality per minute
    function setCardinalityPerMinute(uint8 cardinalityPerMinute) external;

    /// @notice Inserts a new fee tier
    /// @dev Will revert if the given tier is invalid, or already supported
    /// @param feeTier The new fee tier to add
    function insertFeeTier(uint24 feeTier) external;
}
