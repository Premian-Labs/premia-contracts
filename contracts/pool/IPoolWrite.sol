// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @notice Pool option writing interface
 */
interface IPoolWrite {
    /**
     * @notice calculate price of option contract
     * @param feePayer address of the fee payer
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     * @return baseCost64x64 64x64 fixed point representation of option cost denominated in underlying currency (without fee)
     * @return feeCost64x64 64x64 fixed point representation of option fee cost denominated in underlying currency for call, or base currency for put
     * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
     * @return slippageCoefficient64x64 64x64 fixed point representation of slippage coefficient for given order size
     */
    function quote(
        address feePayer,
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall
    )
        external
        view
        returns (
            int128 baseCost64x64,
            int128 feeCost64x64,
            int128 cLevel64x64,
            int128 slippageCoefficient64x64
        );

    /**
     * @notice purchase option
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     * @param maxCost maximum acceptable cost after accounting for slippage
     * @return baseCost quantity of tokens required to purchase long position
     * @return feeCost quantity of tokens required to pay fees
     */
    function purchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost
    ) external payable returns (uint256 baseCost, uint256 feeCost);

    /**
     * @notice swap tokens and purchase option
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     * @param maxCost maximum acceptable cost after accounting for slippage
     * @param amountOut amount out of tokens requested. If 0, we will swap exact amount necessary to pay the quote
     * @param amountInMax amount in max of tokens
     * @param path swap path
     * @param isSushi whether we use sushi or uniV2 for the swap
     * @return baseCost quantity of tokens required to purchase long position
     * @return feeCost quantity of tokens required to pay fees
     */
    function swapAndPurchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        bool isSushi
    ) external payable returns (uint256 baseCost, uint256 feeCost);

    /**
     * @notice write option without using liquidity from the pool on behalf of another address
     * @param underwriter underwriter of the option from who collateral will be deposited
     * @param longReceiver address who will receive the long token (Can be the underwriter)
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize quantity of option contract tokens to exercise
     * @param isCall whether this is a call or a put
     * @return longTokenId token id of the long call
     * @return shortTokenId token id of the short call
     */
    function writeFrom(
        address underwriter,
        address longReceiver,
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall
    ) external payable returns (uint256 longTokenId, uint256 shortTokenId);

    /**
     * @notice force update of oracle price and pending deposit pool
     */
    function update() external;
}
