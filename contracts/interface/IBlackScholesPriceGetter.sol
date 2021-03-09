// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IPriceOracleGetter.sol";

/**
 * @title IBlackScholesPriceGetter interface
 * @notice Interface for the Premia black scholes price oracle.
 */
interface IBlackScholesPriceGetter is IPriceOracleGetter {
    function getBlackScholesEstimate(address _optionContract, uint256 _optionId) external view returns (uint256);

    /**
     * @dev returns the asset price in ETH
     */
    function getAssetPrice(address _asset) override external view returns (uint256);
}