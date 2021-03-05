// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IPriceOracleGetter interface
 * @notice Interface for the Premia price oracle.
 */
interface IPriceOracleGetter {
    /**
     * @dev returns the asset price in ETH
     */
    function getAssetPrice(address _asset) external view returns (uint256);
}