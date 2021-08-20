// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolWrite {
    // sellToken The `sellTokenAddress` field from the 0x API response.
    // buyToken The `buyTokenAddress` field from the 0x API response.
    // spender The `allowanceTarget` field from the 0x API response.
    // swapTarget The `to` field from the 0x API response.
    // maxSellAmount The maximum amount of tokens to sell : `guaranteedPrice` field from the 0x API response multiplied by `buyTokenAmount`
    struct SwapArgs {
        address sellToken;
        address buyToken;
        address spender;
        address swapTarget;
        uint256 maxSellAmount;
        bytes swapCallData;
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
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        bool isSushi
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
