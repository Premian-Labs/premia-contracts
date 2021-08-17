// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

library OptionMath {
    using ABDKMath64x64 for int128;

    struct QuoteArgs {
        int128 emaVarianceAnnualized64x64; // 64x64 fixed point representation of annualized EMA of variance
        int128 strike64x64; // 64x64 fixed point representation of strike price
        int128 spot64x64; // 64x64 fixed point representation of spot price
        int128 timeToMaturity64x64; // 64x64 fixed point representation of duration of option contract (in years)
        int128 oldCLevel64x64; // 64x64 fixed point representation of C-Level of Pool before purchase
        int128 oldPoolState; // 64x64 fixed point representation of current state of the pool
        int128 newPoolState; // 64x64 fixed point representation of state of the pool after trade
        int128 steepness64x64; // 64x64 fixed point representation of Pool state delta multiplier
        int128 minAPY64x64; // 64x64 fixed point representation of minimum APY for capital locked up to underwrite options
        bool isCall; // whether to price "call" or "put" option
    }

    struct CalculateCLevelDecayArgs {
        uint256 timeIntervalsElapsed; // quantity of discrete arbitrary intervals elapsed since last update
        int128 oldCLevel64x64; // C-Level prior to accounting for decay
        int128 utilization64x64; // pool capital utilization rate
        int128 utilizationLowerBound64x64;
        int128 utilizationUpperBound64x64;
        int128 cLevelLowerBound64x64;
        int128 cLevelUpperBound64x64;
        int128 cConvergenceULowerBound64x64;
        int128 cConvergenceUUpperBound64x64;
    }

    // 64x64 fixed point integer constants
    int128 internal constant ONE_64x64 = 0x10000000000000000;
    int128 internal constant THREE_64x64 = 0x30000000000000000;

    // 64x64 fixed point constants used in Choudhury’s approximation of the Black-Scholes CDF
    int128 private constant CDF_CONST_0 = 0x09109f285df452394; // 2260 / 3989
    int128 private constant CDF_CONST_1 = 0x19abac0ea1da65036; // 6400 / 3989
    int128 private constant CDF_CONST_2 = 0x0d3c84b78b749bd6b; // 3300 / 3989

    /**
     * @notice calculate the rolling EMA variance of an uneven time series
     * @param oldEmaLogReturns64x64 64x64 fixed point representation of previous EMA
     * @param oldEmaVariance64x64 64x64 fixed point representation of previous variance
     * @param logReturns64x64 64x64 fixed point representation of natural log of rate of return for current period
     * @param oldTimestamp timestamp of previous update
     * @param newTimestamp current timestamp
     * @return emaLogReturns64x64 64x64 fixed point representation of EMA of natural log of rate of returns
     * @return emaVariance64x64 64x64 fixed point representation of EMA of variance
     */
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
        int128 delta64x64 = ABDKMath64x64.divu(
            newTimestamp - oldTimestamp,
            1 hours
        );
        int128 omega64x64 = _decay(oldTimestamp, newTimestamp);
        emaLogReturns64x64 = _unevenRollingEma(
            oldEmaLogReturns64x64,
            logReturns64x64,
            oldTimestamp,
            newTimestamp
        );

        // v = (1 - decay) * var_prev + (decay * (current - m_prev) * (current - m)) / delta_t
        emaVariance64x64 = ONE_64x64
            .sub(omega64x64)
            .mul(oldEmaVariance64x64)
            .add(
                omega64x64
                    .mul(logReturns64x64.sub(oldEmaLogReturns64x64))
                    .mul(logReturns64x64.sub(emaLogReturns64x64))
                    .div(delta64x64)
            );
    }

    /**
     * @notice recalculate C-Level based on change in liquidity
     * @param initialCLevel64x64 64x64 fixed point representation of C-Level of Pool before update
     * @param oldPoolState64x64 64x64 fixed point representation of liquidity in pool before update
     * @param newPoolState64x64 64x64 fixed point representation of liquidity in pool after update
     * @param steepness64x64 64x64 fixed point representation of steepness coefficient
     * @return 64x64 fixed point representation of new C-Level
     */
    function calculateCLevel(
        int128 initialCLevel64x64,
        int128 oldPoolState64x64,
        int128 newPoolState64x64,
        int128 steepness64x64
    ) external pure returns (int128) {
        return
            newPoolState64x64
                .sub(oldPoolState64x64)
                .div(
                    oldPoolState64x64 > newPoolState64x64
                        ? oldPoolState64x64
                        : newPoolState64x64
                )
                .mul(steepness64x64)
                .neg()
                .exp()
                .mul(initialCLevel64x64);
    }

    /**
     * @notice calculate the price of an option using the Premia Finance model
     * @param args arguments of quotePrice
     * @return premiaPrice64x64 64x64 fixed point representation of Premia option price
     * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
     */
    function quotePrice(QuoteArgs memory args)
        external
        pure
        returns (
            int128 premiaPrice64x64,
            int128 cLevel64x64,
            int128 slippageCoefficient64x64
        )
    {
        int128 deltaPoolState64x64 = args
            .newPoolState
            .sub(args.oldPoolState)
            .div(args.oldPoolState)
            .mul(args.steepness64x64);
        int128 tradingDelta64x64 = deltaPoolState64x64.neg().exp();

        int128 bsPrice64x64 = _bsPrice(
            args.emaVarianceAnnualized64x64,
            args.strike64x64,
            args.spot64x64,
            args.timeToMaturity64x64,
            args.isCall
        );

        cLevel64x64 = tradingDelta64x64.mul(args.oldCLevel64x64);
        slippageCoefficient64x64 = ONE_64x64.sub(tradingDelta64x64).div(
            deltaPoolState64x64
        );

        premiaPrice64x64 = bsPrice64x64.mul(cLevel64x64).mul(
            slippageCoefficient64x64
        );

        int128 intrinsicValue64x64;

        if (args.isCall && args.strike64x64 < args.spot64x64) {
            intrinsicValue64x64 = args.spot64x64.sub(args.strike64x64);
        } else if (!args.isCall && args.strike64x64 > args.spot64x64) {
            intrinsicValue64x64 = args.strike64x64.sub(args.spot64x64);
        }

        int128 collateralValue64x64 = args.isCall
            ? args.spot64x64
            : args.strike64x64;

        int128 minPrice64x64 = intrinsicValue64x64.add(
            collateralValue64x64.mul(args.minAPY64x64).mul(
                args.timeToMaturity64x64
            )
        );

        if (minPrice64x64 > premiaPrice64x64) {
            premiaPrice64x64 = minPrice64x64;
        }
    }

    /**
     * @notice calculate the decay of C-Level based on heat diffusion function
     * @param args structured CalculateCLevelDecayArgs
     * @return cLevelDecayed64x64 C-Level after accounting for decay
     */
    function calculateCLevelDecay(CalculateCLevelDecayArgs memory args)
        internal
        pure
        returns (int128 cLevelDecayed64x64)
    {
        int128 convFHighU64x64 = (args.utilization64x64 >=
            args.utilizationUpperBound64x64 &&
            args.oldCLevel64x64 <= args.cLevelLowerBound64x64)
            ? ONE_64x64
            : int128(0);

        int128 convFLowU64x64 = (args.utilization64x64 <=
            args.utilizationLowerBound64x64 &&
            args.oldCLevel64x64 >= args.cLevelUpperBound64x64)
            ? ONE_64x64
            : int128(0);

        cLevelDecayed64x64 = args
            .oldCLevel64x64
            .sub(args.cConvergenceULowerBound64x64.mul(convFLowU64x64))
            .sub(args.cConvergenceUUpperBound64x64.mul(convFHighU64x64))
            .mul(
                convFLowU64x64
                    .mul(ONE_64x64.sub(args.utilization64x64))
                    .add(convFHighU64x64.mul(args.utilization64x64))
                    .mul(ABDKMath64x64.fromUInt(args.timeIntervalsElapsed))
                    .neg()
                    .exp()
            )
            .add(
                args.cConvergenceULowerBound64x64.mul(convFLowU64x64).add(
                    args.cConvergenceULowerBound64x64.mul(convFHighU64x64)
                )
            );
    }

    /**
     * @notice calculate the exponential decay coefficient for a given interval
     * @param oldTimestamp timestamp of previous update
     * @param newTimestamp current timestamp
     * @return 64x64 fixed point representation of exponential decay coefficient
     */
    function _decay(uint256 oldTimestamp, uint256 newTimestamp)
        internal
        pure
        returns (int128)
    {
        return
            ONE_64x64.sub(
                (-ABDKMath64x64.divu(newTimestamp - oldTimestamp, 7 days)).exp()
            );
    }

    /**
     * @notice calculate the rolling EMA of an uneven time series
     * @param oldEmaLogReturns64x64 64x64 fixed point representation of previous EMA
     * @param logReturns64x64 64x64 fixed point representation of natural log of rate of return for current period
     * @param oldTimestamp timestamp of previous update
     * @param newTimestamp current timestamp
     * @return 64x64 fixed point representation of EMA
     */
    function _unevenRollingEma(
        int128 oldEmaLogReturns64x64,
        int128 logReturns64x64,
        uint256 oldTimestamp,
        uint256 newTimestamp
    ) internal pure returns (int128) {
        int128 decay64x64 = _decay(oldTimestamp, newTimestamp);

        return
            logReturns64x64.mul(decay64x64).add(
                ONE_64x64.sub(decay64x64).mul(oldEmaLogReturns64x64)
            );
    }

    /**
     * @notice calculate Choudhury’s approximation of the Black-Scholes CDF
     * @param input64x64 64x64 fixed point representation of random variable
     * @return 64x64 fixed point representation of the approximated CDF of x
     */
    function _N(int128 input64x64) internal pure returns (int128) {
        // squaring via mul is cheaper than via pow
        int128 inputSquared64x64 = input64x64.mul(input64x64);

        int128 value64x64 = (-inputSquared64x64 >> 1).exp().div(
            CDF_CONST_0.add(CDF_CONST_1.mul(input64x64.abs())).add(
                CDF_CONST_2.mul(inputSquared64x64.add(THREE_64x64).sqrt())
            )
        );

        return input64x64 > 0 ? ONE_64x64.sub(value64x64) : value64x64;
    }

    /**
     * @notice calculate the price of an option using the Black-Scholes model
     * @param emaVarianceAnnualized64x64 64x64 fixed point representation of annualized EMA of variance
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param spot64x64 64x64 fixed point representation of spot price
     * @param timeToMaturity64x64 64x64 fixed point representation of duration of option contract (in years)
     * @param isCall whether to price "call" or "put" option
     * @return 64x64 fixed point representation of Black-Scholes option price
     */
    function _bsPrice(
        int128 emaVarianceAnnualized64x64,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) internal pure returns (int128) {
        int128 cumulativeVariance64x64 = timeToMaturity64x64.mul(
            emaVarianceAnnualized64x64
        );
        int128 cumulativeVarianceSqrt64x64 = cumulativeVariance64x64.sqrt();

        // ToDo : Ensure we never have division by 0 / price of 0
        int128 d1_64x64 = spot64x64
            .div(strike64x64)
            .ln()
            .add(cumulativeVariance64x64 >> 1)
            .div(cumulativeVarianceSqrt64x64);
        int128 d2_64x64 = d1_64x64.sub(cumulativeVarianceSqrt64x64);

        if (isCall) {
            return
                spot64x64.mul(_N(d1_64x64)).sub(strike64x64.mul(_N(d2_64x64)));
        } else {
            return
                -spot64x64.mul(_N(-d1_64x64)).sub(
                    strike64x64.mul(_N(-d2_64x64))
                );
        }
    }
}
