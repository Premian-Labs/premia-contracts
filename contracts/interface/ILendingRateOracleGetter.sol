// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
* @title ILendingRateOracle interface
* @notice Interface for the Aave borrow rate oracle. Provides the average market borrow rate to be used as a base for the stable borrow rate calculations
**/

interface ILendingRateOracleGetter {
    /**
    @dev returns the market borrow rate in ray
    **/
    function getMarketBorrowRate(address _asset) external view returns (uint256);
}