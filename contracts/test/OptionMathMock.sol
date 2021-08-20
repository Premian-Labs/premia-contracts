// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OptionMath} from "../libraries/OptionMath.sol";

contract OptionMathMock {
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

    function N(int128 x) external pure returns (int128) {
        return OptionMath._N(x);
    }

    function blackScholesPrice(
        int128 variance,
        int128 strike,
        int128 price,
        int128 timeToMaturity,
        bool isCall
    ) external pure returns (int128) {
        return
            OptionMath._blackScholesPrice(
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
