// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OptionMath} from "../libraries/OptionMath.sol";

contract OptionMathMock {
    function unevenRollingEmaVariance(
        int128 oldEmaLogReturns64x64,
        int128 oldEmaVariance64x64,
        int128 logReturns64x64,
        uint256 oldTimestamp,
        uint256 newTimestamp
    )
        external
        pure
        returns (int128 emaLogReturns64x64, int128 emaVariance64x64)
    {
        return
            OptionMath.unevenRollingEmaVariance(
                oldEmaLogReturns64x64,
                oldEmaVariance64x64,
                logReturns64x64,
                oldTimestamp,
                newTimestamp
            );
    }

    function calculateCLevel(
        int128 initialCLevel64x64,
        int128 oldPoolState64x64,
        int128 newPoolState64x64,
        int128 steepness64x64
    ) external pure returns (int128) {
        return
            OptionMath.calculateCLevel(
                initialCLevel64x64,
                oldPoolState64x64,
                newPoolState64x64,
                steepness64x64
            );
    }

    function quotePrice(OptionMath.QuoteArgs memory args)
        external
        pure
        returns (
            int128 premiaPrice64x64,
            int128 cLevel64x64,
            int128 slippageCoefficient64x64
        )
    {
        return OptionMath.quotePrice(args);
    }

    function decay(uint256 oldTimestamp, uint256 newTimestamp)
        external
        pure
        returns (int128)
    {
        return OptionMath._decay(oldTimestamp, newTimestamp);
    }

    function unevenRollingEma(
        int128 oldEma64x64,
        int128 logReturns64x64,
        uint256 oldTimestamp,
        uint256 newTimestamp
    ) external pure returns (int128) {
        return
            OptionMath._unevenRollingEma(
                oldEma64x64,
                logReturns64x64,
                oldTimestamp,
                newTimestamp
            );
    }

    function N(int128 x) external pure returns (int128) {
        return OptionMath._N(x);
    }

    function bsPrice(
        int128 variance,
        int128 strike,
        int128 price,
        int128 timeToMaturity,
        bool isCall
    ) external pure returns (int128) {
        return
            OptionMath._bsPrice(
                variance,
                strike,
                price,
                timeToMaturity,
                isCall
            );
    }

    function calculateCLevelDecay(
        OptionMath.CalculateCLevelDecayArgs memory args
    ) external pure returns (int128 cLevelDecayed64x64) {
        return OptionMath.calculateCLevelDecay(args);
    }
}
