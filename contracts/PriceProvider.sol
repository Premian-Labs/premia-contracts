// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/access/Ownable.sol';

/// @author Premia
/// @title Provide token prices in USD, in order to calculate PremiaUncut reward to give to users.
///        Prices will be updated manually every few days, as this use case doesnt really require very accurate price data
contract PriceProvider is Ownable {
    // Token -> Price
    mapping (address => uint256) prices;

    ////////////
    // Events //
    ////////////

    event PriceUpdated(address indexed token, uint256 price);

    /// @notice Set prices for a list of tokens
    /// @param _tokens The list of tokens for which we set prices
    /// @param _prices The list of prices
    function setTokenPrices(address[] memory _tokens, uint256[] memory _prices) external onlyOwner {
        require(_tokens.length == _prices.length, "Array must have same length");

        for (uint256 i=0; i < _tokens.length; i++) {
            prices[_tokens[i]] = _prices[i];
            emit PriceUpdated(_tokens[i], _prices[i]);
        }
    }

    /// @notice Get the usd price of a token
    /// @param _token The token from which to get the price
    /// @return The usd price
    function getTokenPrice(address _token) external view returns(uint256) {
        return prices[_token];
    }
}
