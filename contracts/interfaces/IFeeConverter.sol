// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IFeeConverter {
    event Converted(
        address indexed account,
        address indexed token,
        uint256 inAmount,
        uint256 outAmount,
        uint256 treasuryAmount
    );

    event SetAuthorized(address indexed account, bool isAuthorized);

    /**
     * @notice get the exchange helper address
     * @return exchangeHelper exchange helper address
     */
    function getExchangeHelper() external view returns (address exchangeHelper);

    /**
     * @notice convert held tokens to USDC and distribute as rewards
     * @param sourceToken address of token to convert
     * @param callee exchange address to call to execute the trade.
     * @param allowanceTarget address for which to set allowance for the trade
     * @param data calldata to execute the trade
     */
    function convert(
        address sourceToken,
        address callee,
        address allowanceTarget,
        bytes calldata data
    ) external;
}
