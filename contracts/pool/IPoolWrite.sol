// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolWrite {
    struct SwapArgs {
        uint256 amountOut; // mount out of tokens requested. If 0, we will swap exact amount necessary to pay the quote
        uint256 amountInMax; // amount in max of tokens
        address[] path; // swap path
        bool isSushi; // whether we use sushi or uniV2 for the swap
    }

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

    function purchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost
    ) external payable returns (uint256 baseCost, uint256 feeCost);

    function swapAndPurchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost,
        SwapArgs memory swapArgs
    ) external payable returns (uint256 baseCost, uint256 feeCost);

    function writeFrom(
        address underwriter,
        address longReceiver,
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall
    ) external payable returns (uint256 longTokenId, uint256 shortTokenId);

    function update() external;
}
