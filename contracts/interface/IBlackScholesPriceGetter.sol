// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IBlackScholesPriceGetter interface
 * @notice Interface for the Premia black scholes price oracle.
 */
interface IBlackScholesPriceGetter {
    function getBlackScholesEstimate(address optionContract, uint256 optionId) external view returns (uint256);
}