// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IOptionMath {
    struct QuoteArgs {
        int128 emaVarianceAnnualized64x64;    // 64x64 fixed point representation of annualized EMA of variance
        int128 strike64x64;                   // 64x64 fixed point representation of strike price
        int128 spot64x64;                     // 64x64 fixed point representation of spot price
        int128 timeToMaturity64x64;           // 64x64 fixed point representation of duration of option contract (in years)
        int128 oldCLevel64x64;                // 64x64 fixed point representation of C-Level of Pool before purchase
        int128 oldPoolState;                  // 64x64 fixed point representation of current state of the pool
        int128 newPoolState;                  // 64x64 fixed point representation of state of the pool after trade
        int128 steepness64x64;                // 64x64 fixed point representation of Pool state delta multiplier
        bool isCall;                          // whether to price "call" or "put" option
    }

    function unevenRollingEmaVariance (
        int128 oldEmaLogReturns64x64,
        int128 oldEmaVariance64x64,
        int128 logReturns64x64,
        uint256 oldTimestamp,
        uint256 newTimestamp
    ) external pure returns (int128 emaLogReturns64x64, int128 emaVariance64x64);

    function calculateCLevel (
        int128 initialCLevel64x64,
        int128 oldPoolState64x64,
        int128 newPoolState64x64,
        int128 steepness64x64
    ) external pure returns (int128);

    function quotePrice (
        QuoteArgs memory args
    ) external pure returns (int128 premiaPrice64x64, int128 cLevel64x64, int128 slippageCoefficient64x64);
}
