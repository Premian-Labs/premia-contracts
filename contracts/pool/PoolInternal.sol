// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC165} from "@solidstate/contracts/introspection/ERC165.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {ERC1155Enumerable, EnumerableSet, ERC1155EnumerableStorage} from "@solidstate/contracts/token/ERC1155/ERC1155Enumerable.sol";
import {IWETH} from "@solidstate/contracts/utils/IWETH.sol";

import {PoolStorage} from "./PoolStorage.sol";

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {ABDKMath64x64Token} from "../libraries/ABDKMath64x64Token.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {IPremiaFeeDiscount} from "../interface/IPremiaFeeDiscount.sol";
import {IPoolEvents} from "./IPoolEvents.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolInternal is IPoolEvents, ERC1155Enumerable, ERC165 {
    using ABDKMath64x64 for int128;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolStorage for PoolStorage.Layout;

    address internal immutable WETH_ADDRESS;
    address internal immutable FEE_RECEIVER_ADDRESS;
    address internal immutable FEE_DISCOUNT_ADDRESS;

    int128 internal immutable FEE_64x64;

    uint256 internal immutable UNDERLYING_FREE_LIQ_TOKEN_ID;
    uint256 internal immutable BASE_FREE_LIQ_TOKEN_ID;

    uint256 internal immutable UNDERLYING_RESERVED_LIQ_TOKEN_ID;
    uint256 internal immutable BASE_RESERVED_LIQ_TOKEN_ID;

    uint256 internal constant INVERSE_BASIS_POINT = 1e4;
    uint256 internal constant BATCHING_PERIOD = 260;

    constructor(
        address weth,
        address feeReceiver,
        address feeDiscountAddress,
        int128 fee64x64
    ) {
        WETH_ADDRESS = weth;
        FEE_RECEIVER_ADDRESS = feeReceiver;
        // PremiaFeeDiscount contract address
        FEE_DISCOUNT_ADDRESS = feeDiscountAddress;
        FEE_64x64 = fee64x64;

        UNDERLYING_FREE_LIQ_TOKEN_ID = PoolStorage.formatTokenId(
            PoolStorage.TokenType.UNDERLYING_FREE_LIQ,
            0,
            0
        );
        BASE_FREE_LIQ_TOKEN_ID = PoolStorage.formatTokenId(
            PoolStorage.TokenType.BASE_FREE_LIQ,
            0,
            0
        );

        UNDERLYING_RESERVED_LIQ_TOKEN_ID = PoolStorage.formatTokenId(
            PoolStorage.TokenType.UNDERLYING_RESERVED_LIQ,
            0,
            0
        );
        BASE_RESERVED_LIQ_TOKEN_ID = PoolStorage.formatTokenId(
            PoolStorage.TokenType.BASE_RESERVED_LIQ,
            0,
            0
        );
    }

    function _getFeeDiscount(address feePayer)
        internal
        view
        returns (uint256 discount)
    {
        if (FEE_DISCOUNT_ADDRESS != address(0)) {
            discount = IPremiaFeeDiscount(FEE_DISCOUNT_ADDRESS).getDiscount(
                feePayer
            );
        }
    }

    function _getFeeWithDiscount(address feePayer, uint256 fee)
        internal
        view
        returns (uint256)
    {
        uint256 discount = _getFeeDiscount(feePayer);
        return fee - ((fee * discount) / INVERSE_BASIS_POINT);
    }

    function _withdrawFees(bool isCall) internal returns (uint256 amount) {
        uint256 tokenId = _getReservedLiquidityTokenId(isCall);
        amount = balanceOf(FEE_RECEIVER_ADDRESS, tokenId);

        if (amount > 0) {
            _burn(FEE_RECEIVER_ADDRESS, tokenId, amount);
            emit FeeWithdrawal(isCall, amount);
        }
    }

    /**
     * @notice calculate price of option contract
     * @param args structured quote arguments
     * @return baseCost64x64 64x64 fixed point representation of option cost denominated in underlying currency (without fee)
     * @return feeCost64x64 64x64 fixed point representation of option fee cost denominated in underlying currency for call, or base currency for put
     * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
     * @return slippageCoefficient64x64 64x64 fixed point representation of slippage coefficient for given order size
     */
    function _quote(PoolStorage.QuoteArgsInternal memory args)
        internal
        view
        returns (
            int128 baseCost64x64,
            int128 feeCost64x64,
            int128 cLevel64x64,
            int128 slippageCoefficient64x64
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        int128 contractSize64x64 = ABDKMath64x64Token.fromDecimals(
            args.contractSize,
            l.underlyingDecimals
        );
        bool isCall = args.isCall;

        int128 oldLiquidity64x64;

        {
            PoolStorage.BatchData storage batchData = l.nextDeposits[isCall];
            int128 pendingDeposits64x64;

            if (batchData.eta != 0 && block.timestamp >= batchData.eta) {
                pendingDeposits64x64 = ABDKMath64x64Token.fromDecimals(
                    batchData.totalPendingDeposits,
                    l.getTokenDecimals(isCall)
                );
            }

            oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall).add(
                pendingDeposits64x64
            );
            require(oldLiquidity64x64 > 0, "no liq");

            if (pendingDeposits64x64 > 0) {
                cLevel64x64 = l.calculateCLevel(
                    oldLiquidity64x64.sub(pendingDeposits64x64),
                    oldLiquidity64x64,
                    isCall
                );
            } else {
                cLevel64x64 = l.getCLevel(isCall);
            }
        }

        // TODO: validate values without spending gas
        // assert(oldLiquidity64x64 >= newLiquidity64x64);
        // assert(variance64x64 > 0);
        // assert(strike64x64 > 0);
        // assert(spot64x64 > 0);
        // assert(timeToMaturity64x64 > 0);

        int128 price64x64;

        (price64x64, cLevel64x64, slippageCoefficient64x64) = OptionMath
        .quotePrice(
            OptionMath.QuoteArgs(
                args.emaVarianceAnnualized64x64,
                args.strike64x64,
                args.spot64x64,
                ABDKMath64x64.divu(args.maturity - block.timestamp, 365 days),
                cLevel64x64,
                oldLiquidity64x64,
                oldLiquidity64x64.sub(contractSize64x64),
                0x10000000000000000, // 64x64 fixed point representation of 1
                isCall
            )
        );

        baseCost64x64 = isCall
            ? price64x64.mul(contractSize64x64).div(args.spot64x64)
            : price64x64.mul(contractSize64x64);
        feeCost64x64 = baseCost64x64.mul(FEE_64x64);

        int128 discount = ABDKMath64x64.divu(
            _getFeeDiscount(args.feePayer),
            INVERSE_BASIS_POINT
        );
        feeCost64x64 -= feeCost64x64.mul(discount);
    }

    /**
     * @notice burn corresponding long and short option tokens
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param isCall true for call, false for put
     * @param contractSize quantity of option contract tokens to annihilate
     */
    function _annihilate(
        uint64 maturity,
        int128 strike64x64,
        bool isCall,
        uint256 contractSize
    ) internal {
        uint256 longTokenId = PoolStorage.formatTokenId(
            _getTokenType(isCall, true),
            maturity,
            strike64x64
        );
        uint256 shortTokenId = PoolStorage.formatTokenId(
            _getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        _burn(msg.sender, longTokenId, contractSize);
        _burn(msg.sender, shortTokenId, contractSize);

        emit Annihilate(shortTokenId, contractSize);
    }

    /**
     * @notice purchase call option
     * @param l storage layout struct
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param isCall true for call, false for put
     * @param contractSize size of option contract
     * @param newPrice64x64 64x64 fixed point representation of current spot price
     * @return baseCost quantity of tokens required to purchase long position
     * @return feeCost quantity of tokens required to pay fees
     */
    function _purchase(
        PoolStorage.Layout storage l,
        uint64 maturity,
        int128 strike64x64,
        bool isCall,
        uint256 contractSize,
        int128 newPrice64x64
    ) internal returns (uint256 baseCost, uint256 feeCost) {
        require(maturity > block.timestamp, "expired");
        require(contractSize >= l.underlyingMinimum, "too small");

        {
            uint256 size = isCall
                ? contractSize
                : l.fromUnderlyingToBaseDecimals(
                    strike64x64.mulu(contractSize)
                );

            require(
                size <=
                    totalSupply(_getFreeLiquidityTokenId(isCall)) -
                        l.nextDeposits[isCall].totalPendingDeposits,
                "insuf liq"
            );
        }

        int128 cLevel64x64;

        {
            int128 baseCost64x64;
            int128 feeCost64x64;

            (baseCost64x64, feeCost64x64, cLevel64x64, ) = _quote(
                PoolStorage.QuoteArgsInternal(
                    msg.sender,
                    maturity,
                    strike64x64,
                    newPrice64x64,
                    l.emaVarianceAnnualized64x64,
                    contractSize,
                    isCall
                )
            );

            baseCost = ABDKMath64x64Token.toDecimals(
                baseCost64x64,
                l.getTokenDecimals(isCall)
            );
            feeCost = ABDKMath64x64Token.toDecimals(
                feeCost64x64,
                l.getTokenDecimals(isCall)
            );
        }

        uint256 longTokenId = PoolStorage.formatTokenId(
            _getTokenType(isCall, true),
            maturity,
            strike64x64
        );
        uint256 shortTokenId = PoolStorage.formatTokenId(
            _getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        // mint long option token for buyer
        _mint(msg.sender, longTokenId, contractSize);

        int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);
        // burn free liquidity tokens from other underwriters
        _mintShortTokenLoop(l, contractSize, baseCost, shortTokenId, isCall);
        int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

        _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCall);

        // mint reserved liquidity tokens for fee receiver
        _mint(
            FEE_RECEIVER_ADDRESS,
            _getReservedLiquidityTokenId(isCall),
            feeCost
        );

        emit Purchase(
            msg.sender,
            longTokenId,
            contractSize,
            baseCost,
            feeCost,
            newPrice64x64
        );
    }

    /**
     * @notice reassign short position to new underwriter
     * @param l storage layout struct
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param isCall true for call, false for put
     * @param contractSize quantity of option contract tokens to reassign
     * @param newPrice64x64 64x64 fixed point representation of current spot price
     * @return baseCost quantity of tokens required to reassign short position
     * @return feeCost quantity of tokens required to pay fees
     * @return amountOut quantity of liquidity freed
     */
    function _reassign(
        PoolStorage.Layout storage l,
        uint64 maturity,
        int128 strike64x64,
        bool isCall,
        uint256 contractSize,
        int128 newPrice64x64
    )
        internal
        returns (
            uint256 baseCost,
            uint256 feeCost,
            uint256 amountOut
        )
    {
        (baseCost, feeCost) = _purchase(
            l,
            maturity,
            strike64x64,
            isCall,
            contractSize,
            newPrice64x64
        );
        _annihilate(maturity, strike64x64, isCall, contractSize);

        uint256 annihilateAmount = isCall
            ? contractSize
            : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(contractSize));

        amountOut = annihilateAmount - baseCost - feeCost;
    }

    /**
     * @notice exercise call option on behalf of holder
     * @dev used for processing of expired options if passed holder is zero address
     * @param holder owner of long option tokens to exercise
     * @param longTokenId long option token id
     * @param contractSize quantity of tokens to exercise
     */
    function _exercise(
        address holder,
        uint256 longTokenId,
        uint256 contractSize
    ) internal {
        uint64 maturity;
        int128 strike64x64;
        bool isCall;

        bool onlyExpired = holder == address(0);

        {
            PoolStorage.TokenType tokenType;
            (tokenType, maturity, strike64x64) = PoolStorage.parseTokenId(
                longTokenId
            );
            require(
                tokenType == PoolStorage.TokenType.LONG_CALL ||
                    tokenType == PoolStorage.TokenType.LONG_PUT,
                "invalid type"
            );
            require(!onlyExpired || maturity < block.timestamp, "not expired");
            isCall = tokenType == PoolStorage.TokenType.LONG_CALL;
        }

        PoolStorage.Layout storage l = PoolStorage.layout();

        (int128 spot64x64, ) = _update(l);

        if (maturity < block.timestamp) {
            spot64x64 = l.getPriceUpdateAfter(maturity);
        }

        require(
            onlyExpired ||
                (
                    isCall
                        ? (spot64x64 > strike64x64)
                        : (spot64x64 < strike64x64)
                ),
            "not ITM"
        );

        uint256 exerciseValue;
        // option has a non-zero exercise value
        if (isCall) {
            if (spot64x64 > strike64x64) {
                exerciseValue = spot64x64.sub(strike64x64).div(spot64x64).mulu(
                    contractSize
                );
            }
        } else {
            if (spot64x64 < strike64x64) {
                exerciseValue = l.fromUnderlyingToBaseDecimals(
                    strike64x64.sub(spot64x64).mulu(contractSize)
                );
            }
        }

        uint256 totalFee;

        if (onlyExpired) {
            totalFee += _burnLongTokenLoop(
                contractSize,
                exerciseValue,
                longTokenId,
                isCall
            );
        } else {
            // burn long option tokens from sender
            _burn(holder, longTokenId, contractSize);

            if (exerciseValue > 0) {
                uint256 fee = _getFeeWithDiscount(
                    holder,
                    FEE_64x64.mulu(exerciseValue)
                );
                totalFee += fee;

                _pushTo(holder, _getPoolToken(isCall), exerciseValue - fee);

                emit Exercise(
                    holder,
                    longTokenId,
                    contractSize,
                    exerciseValue,
                    fee
                );
            }
        }

        totalFee += _burnShortTokenLoop(
            contractSize,
            exerciseValue,
            PoolStorage.formatTokenId(
                _getTokenType(isCall, false),
                maturity,
                strike64x64
            ),
            isCall
        );

        _mint(
            FEE_RECEIVER_ADDRESS,
            _getReservedLiquidityTokenId(isCall),
            totalFee
        );
    }

    function _mintShortTokenLoop(
        PoolStorage.Layout storage l,
        uint256 contractSize,
        uint256 premium,
        uint256 shortTokenId,
        bool isCall
    ) internal {
        address underwriter;
        uint256 freeLiqTokenId = _getFreeLiquidityTokenId(isCall);
        (, , int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);

        uint256 toPay = isCall
            ? contractSize
            : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(contractSize));

        mapping(address => address) storage queue = l.liquidityQueueAscending[
            isCall
        ];

        while (toPay > 0) {
            underwriter = queue[address(0)];
            uint256 balance = balanceOf(underwriter, freeLiqTokenId);

            // If dust left, we remove underwriter and skip to next
            if (balance < _getMinimumAmount(isCall)) {
                l.removeUnderwriter(underwriter, isCall);
                continue;
            }

            // ToDo : Do we keep this ?
            // if (underwriter == msg.sender) continue;

            if (!l.getReinvestmentStatus(underwriter)) {
                _burn(underwriter, freeLiqTokenId, balance);
                _mint(
                    underwriter,
                    _getReservedLiquidityTokenId(isCall),
                    balance
                );
                continue;
            }

            // amount of liquidity provided by underwriter, accounting for reinvested premium
            uint256 intervalContractSize = ((balance -
                l.pendingDeposits[underwriter][l.nextDeposits[isCall].eta][
                    isCall
                ]) * (toPay + premium)) / toPay;
            if (intervalContractSize == 0) continue;
            if (intervalContractSize > toPay) intervalContractSize = toPay;

            // amount of premium paid to underwriter
            uint256 intervalPremium = (premium * intervalContractSize) / toPay;
            premium -= intervalPremium;
            toPay -= intervalContractSize;

            // burn free liquidity tokens from underwriter
            _burn(
                underwriter,
                freeLiqTokenId,
                intervalContractSize - intervalPremium
            );

            if (isCall == false) {
                // For PUT, conversion to contract amount is done here (Prior to this line, it is token amount)
                intervalContractSize = l.fromBaseToUnderlyingDecimals(
                    strike64x64.inv().mulu(intervalContractSize)
                );
            }

            // mint short option tokens for underwriter
            // toPay == 0 ? contractSize : intervalContractSize : To prevent minting less than amount,
            // because of rounding (Can happen for put, because of fixed point precision)
            _mint(
                underwriter,
                shortTokenId,
                toPay == 0 ? contractSize : intervalContractSize
            );

            emit Underwrite(
                underwriter,
                msg.sender,
                shortTokenId,
                toPay == 0 ? contractSize : intervalContractSize,
                intervalPremium,
                false
            );

            contractSize -= intervalContractSize;
        }
    }

    function _burnLongTokenLoop(
        uint256 contractSize,
        uint256 exerciseValue,
        uint256 longTokenId,
        bool isCall
    ) internal returns (uint256 totalFee) {
        EnumerableSet.AddressSet storage holders = ERC1155EnumerableStorage
        .layout()
        .accountsByToken[longTokenId];

        while (contractSize > 0) {
            address longTokenHolder = holders.at(holders.length() - 1);

            uint256 intervalContractSize = balanceOf(
                longTokenHolder,
                longTokenId
            );
            if (intervalContractSize > contractSize)
                intervalContractSize = contractSize;

            uint256 intervalExerciseValue;

            uint256 fee;
            if (exerciseValue > 0) {
                intervalExerciseValue =
                    (exerciseValue * intervalContractSize) /
                    contractSize;

                fee = _getFeeWithDiscount(
                    longTokenHolder,
                    FEE_64x64.mulu(intervalExerciseValue)
                );
                totalFee += fee;

                exerciseValue -= intervalExerciseValue;
                _pushTo(
                    longTokenHolder,
                    _getPoolToken(isCall),
                    intervalExerciseValue - fee
                );
            }

            contractSize -= intervalContractSize;

            emit Exercise(
                longTokenHolder,
                longTokenId,
                intervalContractSize,
                intervalExerciseValue - fee,
                fee
            );

            _burn(longTokenHolder, longTokenId, intervalContractSize);
        }
    }

    function _burnShortTokenLoop(
        uint256 contractSize,
        uint256 exerciseValue,
        uint256 shortTokenId,
        bool isCall
    ) internal returns (uint256 totalFee) {
        EnumerableSet.AddressSet storage underwriters = ERC1155EnumerableStorage
        .layout()
        .accountsByToken[shortTokenId];
        (, , int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);

        while (contractSize > 0) {
            address underwriter = underwriters.at(underwriters.length() - 1);

            // amount of liquidity provided by underwriter
            uint256 intervalContractSize = balanceOf(underwriter, shortTokenId);
            if (intervalContractSize > contractSize)
                intervalContractSize = contractSize;

            // amount of value claimed by buyer
            uint256 intervalExerciseValue = (exerciseValue *
                intervalContractSize) / contractSize;
            exerciseValue -= intervalExerciseValue;
            contractSize -= intervalContractSize;

            uint256 freeLiq = isCall
                ? intervalContractSize - intervalExerciseValue
                : PoolStorage.layout().fromUnderlyingToBaseDecimals(
                    strike64x64.mulu(intervalContractSize)
                ) - intervalExerciseValue;

            uint256 fee = _getFeeWithDiscount(
                underwriter,
                FEE_64x64.mulu(freeLiq)
            );
            totalFee += fee;

            // mint free liquidity tokens for underwriter
            if (PoolStorage.layout().getReinvestmentStatus(underwriter)) {
                _addToDepositQueue(underwriter, freeLiq - fee, isCall);
            } else {
                _mint(
                    underwriter,
                    _getReservedLiquidityTokenId(isCall),
                    freeLiq - fee
                );
            }
            // burn short option tokens from underwriter
            _burn(underwriter, shortTokenId, intervalContractSize);

            emit AssignExercise(
                underwriter,
                shortTokenId,
                freeLiq - fee,
                intervalContractSize,
                fee
            );
        }
    }

    function _addToDepositQueue(
        address account,
        uint256 amount,
        bool isCallPool
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _mint(account, _getFreeLiquidityTokenId(isCallPool), amount);

        uint256 nextBatch = (block.timestamp / BATCHING_PERIOD) *
            BATCHING_PERIOD +
            BATCHING_PERIOD;
        l.pendingDeposits[account][nextBatch][isCallPool] += amount;

        PoolStorage.BatchData storage batchData = l.nextDeposits[isCallPool];
        batchData.totalPendingDeposits += amount;
        batchData.eta = nextBatch;
    }

    function _processPendingDeposits(PoolStorage.Layout storage l, bool isCall)
        internal
    {
        PoolStorage.BatchData storage data = l.nextDeposits[isCall];

        if (data.eta == 0 || block.timestamp < data.eta) return;

        int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

        _setCLevel(
            l,
            oldLiquidity64x64,
            oldLiquidity64x64.add(
                ABDKMath64x64Token.fromDecimals(
                    data.totalPendingDeposits,
                    l.getTokenDecimals(isCall)
                )
            ),
            isCall
        );

        delete l.nextDeposits[isCall];
    }

    function _getFreeLiquidityTokenId(bool isCall)
        internal
        view
        returns (uint256 freeLiqTokenId)
    {
        freeLiqTokenId = isCall
            ? UNDERLYING_FREE_LIQ_TOKEN_ID
            : BASE_FREE_LIQ_TOKEN_ID;
    }

    function _getReservedLiquidityTokenId(bool isCall)
        internal
        view
        returns (uint256 reservedLiqTokenId)
    {
        reservedLiqTokenId = isCall
            ? UNDERLYING_RESERVED_LIQ_TOKEN_ID
            : BASE_RESERVED_LIQ_TOKEN_ID;
    }

    function _getPoolToken(bool isCall) internal view returns (address token) {
        token = isCall
            ? PoolStorage.layout().underlying
            : PoolStorage.layout().base;
    }

    function _getTokenType(bool isCall, bool isLong)
        internal
        pure
        returns (PoolStorage.TokenType tokenType)
    {
        if (isCall) {
            tokenType = isLong
                ? PoolStorage.TokenType.LONG_CALL
                : PoolStorage.TokenType.SHORT_CALL;
        } else {
            tokenType = isLong
                ? PoolStorage.TokenType.LONG_PUT
                : PoolStorage.TokenType.SHORT_PUT;
        }
    }

    function _getMinimumAmount(bool isCall)
        internal
        view
        returns (uint256 minimumAmount)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        minimumAmount = isCall ? l.underlyingMinimum : l.baseMinimum;
    }

    function _setCLevel(
        PoolStorage.Layout storage l,
        int128 oldLiquidity64x64,
        int128 newLiquidity64x64,
        bool isCallPool
    ) internal {
        int128 cLevel64x64 = l.setCLevel(
            oldLiquidity64x64,
            newLiquidity64x64,
            isCallPool
        );
        emit UpdateCLevel(
            isCallPool,
            cLevel64x64,
            oldLiquidity64x64,
            newLiquidity64x64
        );
    }

    /**
     * @notice calculate and store updated market state
     * @param l storage layout struct
     * @return newPrice64x64 64x64 fixed point representation of current spot price
     * @return newEmaVarianceAnnualized64x64 64x64 fixed point representation of annualized EMA of variance
     */
    function _update(PoolStorage.Layout storage l)
        internal
        returns (int128 newPrice64x64, int128 newEmaVarianceAnnualized64x64)
    {
        uint256 updatedAt = l.updatedAt;

        if (l.updatedAt == block.timestamp) {
            return (
                l.getPriceUpdate(block.timestamp),
                l.emaVarianceAnnualized64x64
            );
        }

        int128 logReturns64x64;
        int128 oldEmaLogReturns64x64;
        int128 newEmaLogReturns64x64;
        int128 oldEmaVarianceAnnualized64x64;

        (
            newPrice64x64,
            logReturns64x64,
            oldEmaLogReturns64x64,
            newEmaLogReturns64x64,
            oldEmaVarianceAnnualized64x64,
            newEmaVarianceAnnualized64x64
        ) = _calculateUpdate(l);

        if (l.getPriceUpdate(block.timestamp) == 0) {
            l.setPriceUpdate(block.timestamp, newPrice64x64);
        }

        l.emaLogReturns64x64 = newEmaLogReturns64x64;
        l.emaVarianceAnnualized64x64 = newEmaVarianceAnnualized64x64;
        l.updatedAt = block.timestamp;

        _processPendingDeposits(l, true);
        _processPendingDeposits(l, false);

        emit UpdateVariance(
            oldEmaLogReturns64x64,
            oldEmaVarianceAnnualized64x64 / (365 * 24),
            logReturns64x64,
            updatedAt,
            newEmaVarianceAnnualized64x64
        );
    }

    /**
     * @notice fetch price data from oracle and calculate variance
     * @param l storage layout struct
     * @return newPrice64x64 64x64 fixed point representation of current spot price
     * @return logReturns64x64 64x64 fixed point representation of natural log of rate of return for current period
     * @return oldEmaLogReturns64x64 64x64 fixed point representation of old EMA of natural log of rate of returns
     * @return newEmaLogReturns64x64 64x64 fixed point representation of new EMA of natural log of rate of returns
     * @return oldEmaVarianceAnnualized64x64 64x64 fixed point representation of old annualized EMA of variance
     * @return newEmaVarianceAnnualized64x64 64x64 fixed point representation of new annualized EMA of variance
     */
    function _calculateUpdate(PoolStorage.Layout storage l)
        internal
        view
        returns (
            int128 newPrice64x64,
            int128 logReturns64x64,
            int128 oldEmaLogReturns64x64,
            int128 newEmaLogReturns64x64,
            int128 oldEmaVarianceAnnualized64x64,
            int128 newEmaVarianceAnnualized64x64
        )
    {
        uint256 updatedAt = l.updatedAt;
        require(l.updatedAt != block.timestamp, "alrdy updated");

        int128 oldPrice64x64 = l.getPriceUpdate(updatedAt);
        newPrice64x64 = l.fetchPriceUpdate();

        logReturns64x64 = newPrice64x64.div(oldPrice64x64).ln();
        oldEmaLogReturns64x64 = l.emaLogReturns64x64;
        oldEmaVarianceAnnualized64x64 = l.emaVarianceAnnualized64x64;

        int128 newEmaVariance64x64;

        (newEmaLogReturns64x64, newEmaVariance64x64) = OptionMath
        .unevenRollingEmaVariance(
            oldEmaLogReturns64x64,
            oldEmaVarianceAnnualized64x64 / (365 * 24),
            logReturns64x64,
            updatedAt,
            block.timestamp
        );

        newEmaVarianceAnnualized64x64 = newEmaVariance64x64 * (365 * 24);
    }

    /**
     * @notice transfer ERC20 tokens to message sender
     * @param token ERC20 token address
     * @param amount quantity of token to transfer
     */
    function _pushTo(
        address to,
        address token,
        uint256 amount
    ) internal {
        if (amount == 0) return;

        require(IERC20(token).transfer(to, amount), "ERC20 transfer failed");
    }

    /**
     * @notice transfer ERC20 tokens from message sender
     * @param from address from which tokens are pulled from
     * @param token ERC20 token address
     * @param amount quantity of token to transfer
     */
    function _pullFrom(
        address from,
        address token,
        uint256 amount
    ) internal {
        if (token == WETH_ADDRESS) {
            if (msg.value > 0) {
                require(msg.value <= amount, "too much ETH sent");

                unchecked {
                    amount -= msg.value;
                }

                IWETH(WETH_ADDRESS).deposit{value: msg.value}();
            }
        } else {
            require(msg.value == 0, "not WETH deposit");
        }

        if (amount > 0) {
            require(
                IERC20(token).transferFrom(from, address(this), amount),
                "ERC20 transfer failed"
            );
        }
    }

    function _mint(
        address account,
        uint256 tokenId,
        uint256 amount
    ) internal {
        // TODO: incorporate into SolidState
        _mint(account, tokenId, amount, "");
    }

    /**
     * @notice ERC1155 hook: track eligible underwriters
     * @param operator transaction sender
     * @param from token sender
     * @param to token receiver
     * @param ids token ids transferred
     * @param amounts token quantities transferred
     * @param data data payload
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        // TODO: use linked list for ERC1155Enumerable

        PoolStorage.Layout storage l = PoolStorage.layout();

        for (uint256 i; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            if (amount == 0) continue;

            if (from == address(0)) {
                l.tokenIds.add(id);
            }

            if (to == address(0) && totalSupply(id) == 0) {
                l.tokenIds.remove(id);
            }

            if (
                id == UNDERLYING_FREE_LIQ_TOKEN_ID ||
                id == BASE_FREE_LIQ_TOKEN_ID
            ) {
                bool isCallPool = id == UNDERLYING_FREE_LIQ_TOKEN_ID;
                uint256 minimum = _getMinimumAmount(isCallPool);

                if (from != address(0)) {
                    if (to != address(0)) {
                        require(
                            l.depositedAt[from][isCallPool] + (1 days) <
                                block.timestamp,
                            "liq lock 1d"
                        );
                    }

                    uint256 balance = balanceOf(from, id);

                    if (balance > minimum && balance <= amount + minimum) {
                        require(
                            balance -
                                l.pendingDeposits[from][
                                    l.nextDeposits[isCallPool].eta
                                ][isCallPool] >=
                                amount,
                            "Insuf balance"
                        );
                        l.removeUnderwriter(from, isCallPool);
                    }
                }

                if (to != address(0)) {
                    uint256 balance = balanceOf(to, id);

                    if (balance <= minimum && balance + amount > minimum) {
                        l.addUnderwriter(to, isCallPool);
                    }
                }
            }
        }
    }
}
