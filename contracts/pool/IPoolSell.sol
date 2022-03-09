// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPoolSell {
    /**
     * @notice Enable or disable buyback
     * @param state whether to enable or disable buyback
     */
    function setBuybackEnabled(bool state, bool isCallPool) external;

    /**
     * @notice Get whether buyback is enabled or not for a given LP
     * @param account LP account for which to check
     * @return whether buyback is enabled or not
     */
    function isBuybackEnabled(address account, bool isCallPool)
        external
        view
        returns (bool);

    /**
     * @notice calculate the total available buyback liquidity for an option
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param isCall true for call, false for put
     * @return total available buyback liquidity for this option
     */
    function getAvailableBuybackLiquidity(
        uint64 maturity,
        int128 strike64x64,
        bool isCall
    ) external view returns (uint256);

    /**
     * @notice calculate price of option contract
     * @param feePayer address of the fee payer
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     * @return baseCost64x64 64x64 fixed point representation of option cost denominated in underlying currency (without fee)
     * @return feeCost64x64 64x64 fixed point representation of option fee cost denominated in underlying currency for call, or base currency for put
     */
    function sellQuote(
        address feePayer,
        uint64 maturity,
        int128 strike64x64,
        int128 spot64x64,
        uint256 contractSize,
        bool isCall
    ) external view returns (int128 baseCost64x64, int128 feeCost64x64);

    /**
     * @notice sell options back to the pool to LP who enabled buyback
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     */
    function sell(
        uint64 maturity,
        int128 strike64x64,
        bool isCall,
        uint256 contractSize
    ) external;
}
