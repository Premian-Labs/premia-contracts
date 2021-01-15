// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/access/Ownable.sol';

// Contract used to provide token prices in USD, in order to calculate PremiaUncut reward to give to users.
// Prices will be updated manually every few days, as this use case doesnt really require very accurate price data
contract PriceProvider is Ownable {
    mapping (address => uint256) prices;

    event PriceUpdated(address indexed token, uint256 price);

    function setTokenPrices(address[] memory _tokens, uint256[] memory _prices) external onlyOwner {
        require(_tokens.length == _prices.length, "Array must have same length");

        for (uint256 i=0; i < _tokens.length; i++) {
            prices[_tokens[i]] = _prices[i];
            emit PriceUpdated(_tokens[i], _prices[i]);
        }
    }

    function getTokenPrice(address _token) external view returns(uint256) {
        return prices[_token];
    }
}
