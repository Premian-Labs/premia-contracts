// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC173} from "@solidstate/contracts/access/IERC173.sol";
import {OwnableStorage} from "@solidstate/contracts/access/OwnableStorage.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {ERC1155EnumerableInternal, ERC1155EnumerableStorage, EnumerableSet} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {ERC1155BaseStorage} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseStorage.sol";
import {IWETH} from "@solidstate/contracts/utils/IWETH.sol";

import {PoolStorage} from "./PoolStorage.sol";

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {ABDKMath64x64Token} from "../libraries/ABDKMath64x64Token.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {IFeeDiscount} from "../staking/IFeeDiscount.sol";
import {IPoolEvents} from "./IPoolEvents.sol";
import {IPremiaMining} from "../mining/IPremiaMining.sol";
import {IVolatilitySurfaceOracle} from "../oracle/IVolatilitySurfaceOracle.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolInternal is IPoolEvents, ERC1155EnumerableInternal {
    using ABDKMath64x64 for int128;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolStorage for PoolStorage.Layout;

    address internal immutable WETH_ADDRESS;
    address internal immutable PREMIA_MINING_ADDRESS;
    address internal immutable FEE_RECEIVER_ADDRESS;
    address internal immutable FEE_DISCOUNT_ADDRESS;
    address internal immutable IVOL_ORACLE_ADDRESS;

    int128 internal immutable FEE_64x64;

    uint256 internal immutable UNDERLYING_FREE_LIQ_TOKEN_ID;
    uint256 internal immutable BASE_FREE_LIQ_TOKEN_ID;

    uint256 internal immutable UNDERLYING_RESERVED_LIQ_TOKEN_ID;
    uint256 internal immutable BASE_RESERVED_LIQ_TOKEN_ID;

    uint256 internal constant INVERSE_BASIS_POINT = 1e4;
    uint256 internal constant BATCHING_PERIOD = 260;

    // Minimum APY for capital locked up to underwrite options.
    // The quote will return a minimum price corresponding to this APY
    int128 internal constant MIN_APY_64x64 = 0x4ccccccccccccccd; // 0.3

    // This constant is used to replace real exponent by an integer with 4 decimals of precision
    int128 internal constant SELL_CONSTANT_64x64 = 0x100068dce3484dce2; // e^(1 / 10^4)
    uint256 internal constant SELL_CONSTANT_PRECISION = 4; // Decimals of precision to use with the sell constant

    constructor(
        address ivolOracle,
        address weth,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 fee64x64
    ) {
        IVOL_ORACLE_ADDRESS = ivolOracle;
        WETH_ADDRESS = weth;
        PREMIA_MINING_ADDRESS = premiaMining;
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

    modifier onlyProtocolOwner() {
        require(
            msg.sender == IERC173(OwnableStorage.layout().owner).owner(),
            "Not protocol owner"
        );
        _;
    }

    function _getFeeDiscount(address feePayer)
        internal
        view
        returns (uint256 discount)
    {
        if (FEE_DISCOUNT_ADDRESS != address(0)) {
            discount = IFeeDiscount(FEE_DISCOUNT_ADDRESS).getDiscount(feePayer);
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
        amount = _balanceOf(FEE_RECEIVER_ADDRESS, tokenId);

        if (amount > 0) {
            _burn(FEE_RECEIVER_ADDRESS, tokenId, amount);
            emit FeeWithdrawal(isCall, amount);
        }
    }

    /**
     * @notice calculate price of option contract
     * @param args structured quote arguments
     * @return result quote result
     */
    function _quote(PoolStorage.QuoteArgsInternal memory args)
        internal
        view
        returns (PoolStorage.QuoteResultInternal memory result)
    {
        require(
            args.strike64x64 > 0 && args.spot64x64 > 0 && args.maturity > 0,
            "invalid args"
        );

        PoolStorage.Layout storage l = PoolStorage.layout();

        int128 contractSize64x64 = ABDKMath64x64Token.fromDecimals(
            args.contractSize,
            l.underlyingDecimals
        );

        (int128 adjustedCLevel64x64, int128 oldLiquidity64x64) = l
            .getRealPoolState(args.isCall);

        require(oldLiquidity64x64 > 0, "no liq");

        int128 timeToMaturity64x64 = ABDKMath64x64.divu(
            args.maturity - block.timestamp,
            365 days
        );

        int128 annualizedVolatility64x64 = IVolatilitySurfaceOracle(
            IVOL_ORACLE_ADDRESS
        ).getAnnualizedVolatility64x64(
                l.base,
                l.underlying,
                args.spot64x64,
                args.strike64x64,
                timeToMaturity64x64
            );

        require(annualizedVolatility64x64 > 0, "vol = 0");

        int128 collateral64x64 = args.isCall
            ? contractSize64x64
            : contractSize64x64.mul(args.strike64x64);

        (
            int128 price64x64,
            int128 cLevel64x64,
            int128 slippageCoefficient64x64
        ) = OptionMath.quotePrice(
                OptionMath.QuoteArgs(
                    annualizedVolatility64x64.mul(annualizedVolatility64x64),
                    args.strike64x64,
                    args.spot64x64,
                    timeToMaturity64x64,
                    adjustedCLevel64x64,
                    oldLiquidity64x64,
                    oldLiquidity64x64.sub(collateral64x64),
                    0x10000000000000000, // 64x64 fixed point representation of 1
                    MIN_APY_64x64,
                    args.isCall
                )
            );

        result.baseCost64x64 = args.isCall
            ? price64x64.mul(contractSize64x64).div(args.spot64x64)
            : price64x64.mul(contractSize64x64);
        result.feeCost64x64 = result.baseCost64x64.mul(FEE_64x64);
        result.cLevel64x64 = cLevel64x64;
        result.slippageCoefficient64x64 = slippageCoefficient64x64;

        int128 discount64x64 = ABDKMath64x64.divu(
            _getFeeDiscount(args.feePayer),
            INVERSE_BASIS_POINT
        );
        result.feeCost64x64 -= result.feeCost64x64.mul(discount64x64);
    }

    function _sellQuote(PoolStorage.QuoteArgsInternal memory args)
        internal
        view
        returns (int128 baseCost64x64, int128 feeCost64x64)
    {
        require(
            args.strike64x64 > 0 && args.spot64x64 > 0 && args.maturity > 0,
            "invalid args"
        );

        PoolStorage.Layout storage l = PoolStorage.layout();

        int128 timeToMaturity64x64 = ABDKMath64x64.divu(
            args.maturity - block.timestamp,
            365 days
        );

        int128 annualizedVolatility64x64 = IVolatilitySurfaceOracle(
            IVOL_ORACLE_ADDRESS
        ).getAnnualizedVolatility64x64(
                l.base,
                l.underlying,
                args.spot64x64,
                args.strike64x64,
                timeToMaturity64x64
            );

        require(annualizedVolatility64x64 > 0, "vol = 0");

        int128 blackScholesPrice64x64 = OptionMath._blackScholesPrice(
            annualizedVolatility64x64.mul(annualizedVolatility64x64),
            args.strike64x64,
            args.spot64x64,
            timeToMaturity64x64,
            args.isCall
        );

        int128 exerciseValue64x64 = ABDKMath64x64Token.fromDecimals(
            _calculateExerciseValue(
                l,
                args.contractSize,
                args.spot64x64,
                args.strike64x64,
                args.isCall
            ),
            l.baseDecimals
        );

        uint256 shortTokenId = PoolStorage.formatTokenId(
            _getTokenType(args.isCall, false),
            args.maturity,
            args.strike64x64
        );

        int128 sellCLevel64x64;

        {
            uint256 longTokenId = PoolStorage.formatTokenId(
                _getTokenType(args.isCall, true),
                args.maturity,
                args.strike64x64
            );

            // Initialize to avg value, and replace by current if avg not set or current is lower
            sellCLevel64x64 = l.avgCLevel64x64[longTokenId];

            {
                int128 currentCLevel64x64 = l.getRawCLevel64x64(args.isCall);

                if (
                    sellCLevel64x64 == 0 || currentCLevel64x64 < sellCLevel64x64
                ) {
                    sellCLevel64x64 = currentCLevel64x64;
                }
            }
        }

        uint256 availableLiquidity = _getAvailableBuybackLiquidity(
            shortTokenId
        );

        require(availableLiquidity > 0, "no sell liq");

        uint256 liquidityChange = (args.contractSize *
            (10**SELL_CONSTANT_PRECISION)) / availableLiquidity;

        int128 contractSize64x64 = ABDKMath64x64Token.fromDecimals(
            args.contractSize,
            l.underlyingDecimals
        );

        baseCost64x64 = (SELL_CONSTANT_64x64.pow(liquidityChange))
            .mul(sellCLevel64x64)
            .mul(
                blackScholesPrice64x64.mul(contractSize64x64).sub(
                    exerciseValue64x64
                )
            )
            .add(exerciseValue64x64);

        if (args.isCall) {
            baseCost64x64 = baseCost64x64.div(args.spot64x64);
        }

        feeCost64x64 = baseCost64x64.mul(FEE_64x64);
        int128 discount64x64 = ABDKMath64x64.divu(
            _getFeeDiscount(args.feePayer),
            INVERSE_BASIS_POINT
        );

        feeCost64x64 -= feeCost64x64.mul(discount64x64);
        baseCost64x64 -= feeCost64x64;
    }

    function _getAvailableBuybackLiquidity(uint256 shortTokenId)
        internal
        view
        returns (uint256 totalLiquidity)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        EnumerableSet.AddressSet storage accounts = ERC1155EnumerableStorage
            .layout()
            .accountsByToken[shortTokenId];

        uint256 length = accounts.length();

        for (uint256 i = 0; i < length; i++) {
            address lp = accounts.at(i);

            if (l.isBuyBackEnabled[lp]) {
                totalLiquidity += _balanceOf(lp, shortTokenId);
            }
        }
    }

    /**
     * @notice burn corresponding long and short option tokens
     * @param account holder of tokens to annihilate
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param isCall true for call, false for put
     * @param contractSize quantity of option contract tokens to annihilate
     */
    function _annihilate(
        address account,
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

        _burn(account, longTokenId, contractSize);
        _burn(account, shortTokenId, contractSize);

        emit Annihilate(shortTokenId, contractSize);
    }

    /**
     * @notice deposit underlying currency, underwriting calls of that currency with respect to base currency
     * @param amount quantity of underlying currency to deposit
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     * @param creditMessageValue whether to apply message value as credit towards transfer
     */
    function _deposit(
        uint256 amount,
        bool isCallPool,
        bool creditMessageValue
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        // Reset gradual divestment timestamp
        delete l.divestmentTimestamps[msg.sender][isCallPool];

        uint256 cap = _getPoolCapAmount(l, isCallPool);

        require(
            l.totalTVL[isCallPool] + amount <= cap,
            "pool deposit cap reached"
        );

        _processPendingDeposits(l, isCallPool);

        l.depositedAt[msg.sender][isCallPool] = block.timestamp;
        _addUserTVL(l, msg.sender, isCallPool, amount);
        _pullFrom(
            msg.sender,
            _getPoolToken(isCallPool),
            amount,
            creditMessageValue ? _creditMessageValue(amount, isCallPool) : 0
        );

        _addToDepositQueue(msg.sender, amount, isCallPool);

        emit Deposit(msg.sender, isCallPool, amount);
    }

    /**
     * @notice purchase option
     * @param l storage layout struct
     * @param account recipient of purchased option
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
        address account,
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
                    ERC1155EnumerableStorage.layout().totalSupply[
                        _getFreeLiquidityTokenId(isCall)
                    ] -
                        l.nextDeposits[isCall].totalPendingDeposits,
                "insuf liq"
            );
        }

        PoolStorage.QuoteResultInternal memory quote = _quote(
            PoolStorage.QuoteArgsInternal(
                account,
                maturity,
                strike64x64,
                newPrice64x64,
                contractSize,
                isCall
            )
        );

        baseCost = ABDKMath64x64Token.toDecimals(
            quote.baseCost64x64,
            l.getTokenDecimals(isCall)
        );

        feeCost = ABDKMath64x64Token.toDecimals(
            quote.feeCost64x64,
            l.getTokenDecimals(isCall)
        );

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

        _updateCLevelAverage(l, longTokenId, contractSize, quote.cLevel64x64);

        // mint long option token for buyer
        _mint(account, longTokenId, contractSize);

        int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);
        // burn free liquidity tokens from other underwriters
        _mintShortTokenLoop(
            l,
            account,
            contractSize,
            baseCost,
            shortTokenId,
            isCall
        );
        int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

        _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCall);

        // mint reserved liquidity tokens for fee receiver
        _mint(
            FEE_RECEIVER_ADDRESS,
            _getReservedLiquidityTokenId(isCall),
            feeCost
        );

        emit Purchase(
            account,
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
     * @param account holder of positions to be reassigned
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
        address account,
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
            account,
            maturity,
            strike64x64,
            isCall,
            contractSize,
            newPrice64x64
        );

        _annihilate(account, maturity, strike64x64, isCall, contractSize);

        uint256 annihilateAmount = isCall
            ? contractSize
            : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(contractSize));

        amountOut = annihilateAmount - baseCost - feeCost;
    }

    /**
     * @notice exercise option on behalf of holder
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

        int128 spot64x64 = _update(l);

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

        uint256 exerciseValue = _calculateExerciseValue(
            l,
            contractSize,
            spot64x64,
            strike64x64,
            isCall
        );

        uint256 fee;

        if (onlyExpired) {
            // burn long option tokens from multiple holders
            // transfer profit to and emit Exercise event for each holder in loop

            fee = _burnLongTokenLoop(
                contractSize,
                exerciseValue,
                longTokenId,
                _getPoolToken(isCall)
            );
        } else {
            // burn long option tokens from sender

            fee = _burnLongTokenInterval(
                holder,
                longTokenId,
                contractSize,
                exerciseValue,
                _getPoolToken(isCall)
            );
        }

        // burn short option tokens from multiple underwriters

        _burnShortTokenLoop(
            contractSize,
            exerciseValue,
            PoolStorage.formatTokenId(
                _getTokenType(isCall, false),
                maturity,
                strike64x64
            ),
            isCall
        );

        _mint(FEE_RECEIVER_ADDRESS, _getReservedLiquidityTokenId(isCall), fee);
    }

    function _calculateExerciseValue(
        PoolStorage.Layout storage l,
        uint256 contractSize,
        int128 spot64x64,
        int128 strike64x64,
        bool isCall
    ) internal view returns (uint256 exerciseValue) {
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
    }

    function _mintShortTokenLoop(
        PoolStorage.Layout storage l,
        address buyer,
        uint256 contractSize,
        uint256 premium,
        uint256 shortTokenId,
        bool isCall
    ) internal {
        uint256 freeLiqTokenId = _getFreeLiquidityTokenId(isCall);
        (, , int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);

        uint256 toPay = isCall
            ? contractSize
            : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(contractSize));

        while (toPay > 0) {
            address underwriter = l.liquidityQueueAscending[isCall][address(0)];
            uint256 balance = _balanceOf(underwriter, freeLiqTokenId);

            // If dust left, we remove underwriter and skip to next
            if (balance < _getMinimumAmount(l, isCall)) {
                l.removeUnderwriter(underwriter, isCall);
                continue;
            }

            if (!l.getReinvestmentStatus(underwriter, isCall)) {
                _burn(underwriter, freeLiqTokenId, balance);
                _mint(
                    underwriter,
                    _getReservedLiquidityTokenId(isCall),
                    balance
                );
                _subUserTVL(l, underwriter, isCall, balance);
                continue;
            }

            // amount of liquidity provided by underwriter, accounting for reinvested premium
            uint256 intervalTokenAmount = ((balance -
                l.pendingDeposits[underwriter][l.nextDeposits[isCall].eta][
                    isCall
                ]) * (toPay + premium)) / toPay;
            if (intervalTokenAmount == 0) continue;
            if (intervalTokenAmount > toPay) intervalTokenAmount = toPay;

            // amount of premium paid to underwriter
            uint256 intervalPremium = (premium * intervalTokenAmount) / toPay;
            premium -= intervalPremium;
            toPay -= intervalTokenAmount;
            _addUserTVL(l, underwriter, isCall, intervalPremium);

            // burn free liquidity tokens from underwriter
            _burn(
                underwriter,
                freeLiqTokenId,
                intervalTokenAmount - intervalPremium
            );

            uint256 intervalContractSize;

            if (isCall) {
                intervalContractSize = intervalTokenAmount;
            } else {
                intervalContractSize = l.fromBaseToUnderlyingDecimals(
                    strike64x64.inv().mulu(intervalTokenAmount)
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
                buyer,
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
        address payoutToken
    ) internal returns (uint256 totalFee) {
        EnumerableSet.AddressSet storage holders = ERC1155EnumerableStorage
            .layout()
            .accountsByToken[longTokenId];

        while (contractSize > 0) {
            address longTokenHolder = holders.at(holders.length() - 1);

            uint256 intervalContractSize = _balanceOf(
                longTokenHolder,
                longTokenId
            );

            if (intervalContractSize > contractSize)
                intervalContractSize = contractSize;

            uint256 intervalExerciseValue = (exerciseValue *
                intervalContractSize) / contractSize;

            uint256 fee = _burnLongTokenInterval(
                longTokenHolder,
                longTokenId,
                intervalContractSize,
                intervalExerciseValue,
                payoutToken
            );

            exerciseValue -= intervalExerciseValue;
            contractSize -= intervalContractSize;
            totalFee += fee;
        }
    }

    function _burnLongTokenInterval(
        address holder,
        uint256 longTokenId,
        uint256 contractSize,
        uint256 exerciseValue,
        address payoutToken
    ) internal returns (uint256 fee) {
        _burn(holder, longTokenId, contractSize);

        if (exerciseValue > 0) {
            fee = _getFeeWithDiscount(holder, FEE_64x64.mulu(exerciseValue));

            _pushTo(holder, payoutToken, exerciseValue - fee);
        }

        emit Exercise(holder, longTokenId, contractSize, exerciseValue, fee);
    }

    function _burnShortTokenLoop(
        uint256 contractSize,
        uint256 exerciseValue,
        uint256 shortTokenId,
        bool isCall
    ) internal {
        EnumerableSet.AddressSet storage underwriters = ERC1155EnumerableStorage
            .layout()
            .accountsByToken[shortTokenId];
        (, , int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);

        while (contractSize > 0) {
            address underwriter = underwriters.at(underwriters.length() - 1);

            // amount of liquidity provided by underwriter
            uint256 intervalContractSize = _balanceOf(
                underwriter,
                shortTokenId
            );
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

            uint256 tvlToSubtract = intervalExerciseValue;

            // mint free liquidity tokens for underwriter
            if (
                PoolStorage.layout().getReinvestmentStatus(underwriter, isCall)
            ) {
                _addToDepositQueue(underwriter, freeLiq, isCall);
            } else {
                _mint(
                    underwriter,
                    _getReservedLiquidityTokenId(isCall),
                    freeLiq
                );
                tvlToSubtract += freeLiq;
            }

            _subUserTVL(
                PoolStorage.layout(),
                underwriter,
                isCall,
                tvlToSubtract
            );

            // burn short option tokens from underwriter
            _burn(underwriter, shortTokenId, intervalContractSize);

            emit AssignExercise(
                underwriter,
                shortTokenId,
                freeLiq,
                intervalContractSize,
                0
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

    function _getMinimumAmount(PoolStorage.Layout storage l, bool isCall)
        internal
        view
        returns (uint256 minimumAmount)
    {
        minimumAmount = isCall ? l.underlyingMinimum : l.baseMinimum;
    }

    function _getPoolCapAmount(PoolStorage.Layout storage l, bool isCall)
        internal
        view
        returns (uint256 poolCapAmount)
    {
        poolCapAmount = isCall ? l.underlyingPoolCap : l.basePoolCap;
    }

    function _setCLevel(
        PoolStorage.Layout storage l,
        int128 oldLiquidity64x64,
        int128 newLiquidity64x64,
        bool isCallPool
    ) internal {
        int128 oldCLevel64x64 = l.getDecayAdjustedCLevel64x64(isCallPool);

        int128 cLevel64x64 = l.applyCLevelLiquidityChangeAdjustment(
            oldCLevel64x64,
            oldLiquidity64x64,
            newLiquidity64x64,
            isCallPool
        );

        l.setCLevel(cLevel64x64, isCallPool);

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
     */
    function _update(PoolStorage.Layout storage l)
        internal
        returns (int128 newPrice64x64)
    {
        if (l.updatedAt == block.timestamp) {
            return (l.getPriceUpdate(block.timestamp));
        }

        newPrice64x64 = l.fetchPriceUpdate();

        if (l.getPriceUpdate(block.timestamp) == 0) {
            l.setPriceUpdate(block.timestamp, newPrice64x64);
        }

        l.updatedAt = block.timestamp;

        _processPendingDeposits(l, true);
        _processPendingDeposits(l, false);
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
     * @param credit amount already credited to depositor, to be deducted from transfer
     */
    function _pullFrom(
        address from,
        address token,
        uint256 amount,
        uint256 credit
    ) internal {
        if (amount > credit) {
            require(
                IERC20(token).transferFrom(
                    from,
                    address(this),
                    amount - credit
                ),
                "ERC20 transfer failed"
            );
        }
    }

    /**
     * @notice validate that pool accepts ether deposits and calculate credit amount from message value
     * @param amount total deposit quantity
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     * @return credit quantity of credit to apply
     */
    function _creditMessageValue(uint256 amount, bool isCallPool)
        internal
        returns (uint256 credit)
    {
        if (msg.value > 0) {
            require(
                _getPoolToken(isCallPool) == WETH_ADDRESS,
                "not WETH deposit"
            );

            if (msg.value > amount) {
                unchecked {
                    (bool success, ) = payable(msg.sender).call{
                        value: msg.value - amount
                    }("");

                    require(success, "ETH refund failed");

                    credit = amount;
                }
            } else {
                credit = msg.value;
            }

            IWETH(WETH_ADDRESS).deposit{value: credit}();
        }
    }

    function _mint(
        address account,
        uint256 tokenId,
        uint256 amount
    ) internal {
        _mint(account, tokenId, amount, "");
    }

    function _addUserTVL(
        PoolStorage.Layout storage l,
        address user,
        bool isCallPool,
        uint256 amount
    ) internal {
        uint256 userTVL = l.userTVL[user][isCallPool];
        uint256 totalTVL = l.totalTVL[isCallPool];

        IPremiaMining(PREMIA_MINING_ADDRESS).allocatePending(
            user,
            address(this),
            isCallPool,
            userTVL,
            userTVL + amount,
            totalTVL
        );

        l.userTVL[user][isCallPool] = userTVL + amount;
        l.totalTVL[isCallPool] = totalTVL + amount;
    }

    function _subUserTVL(
        PoolStorage.Layout storage l,
        address user,
        bool isCallPool,
        uint256 amount
    ) internal {
        uint256 userTVL = l.userTVL[user][isCallPool];
        uint256 totalTVL = l.totalTVL[isCallPool];

        uint256 newUserTVL;
        uint256 newTotalTVL;

        if (userTVL > amount) {
            newUserTVL = userTVL - amount;
        }

        if (totalTVL > amount) {
            newTotalTVL = totalTVL - amount;
        }

        IPremiaMining(PREMIA_MINING_ADDRESS).allocatePending(
            user,
            address(this),
            isCallPool,
            userTVL,
            newUserTVL,
            totalTVL
        );

        l.userTVL[user][isCallPool] = newUserTVL;
        l.totalTVL[isCallPool] = newTotalTVL;
    }

    function _updateCLevelAverage(
        PoolStorage.Layout storage l,
        uint256 longTokenId,
        uint256 contractSize,
        int128 cLevel64x64
    ) internal {
        int128 supply64x64 = ABDKMath64x64.divu(
            ERC1155EnumerableStorage.layout().totalSupply[longTokenId],
            10**l.underlyingDecimals
        );
        int128 contractSize64x64 = ABDKMath64x64.divu(
            contractSize,
            10**l.underlyingDecimals
        );

        l.avgCLevel64x64[longTokenId] = l
            .avgCLevel64x64[longTokenId]
            .mul(supply64x64)
            .add(cLevel64x64.mul(contractSize64x64))
            .div(supply64x64.add(contractSize64x64));
    }

    function _setBuyBackEnabled(bool state) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();
        l.isBuyBackEnabled[msg.sender] = state;
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

        PoolStorage.Layout storage l = PoolStorage.layout();

        for (uint256 i; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            if (amount == 0) continue;

            if (from == address(0)) {
                l.tokenIds.add(id);
            }

            if (
                to == address(0) &&
                ERC1155EnumerableStorage.layout().totalSupply[id] == 0
            ) {
                l.tokenIds.remove(id);
            }

            // prevent transfer of free and reserved liquidity during waiting period

            if (
                id == UNDERLYING_FREE_LIQ_TOKEN_ID ||
                id == BASE_FREE_LIQ_TOKEN_ID ||
                id == UNDERLYING_RESERVED_LIQ_TOKEN_ID ||
                id == BASE_RESERVED_LIQ_TOKEN_ID
            ) {
                if (from != address(0) && to != address(0)) {
                    bool isCallPool = id == UNDERLYING_FREE_LIQ_TOKEN_ID ||
                        id == UNDERLYING_RESERVED_LIQ_TOKEN_ID;

                    require(
                        l.depositedAt[from][isCallPool] + (1 days) <
                            block.timestamp,
                        "liq lock 1d"
                    );
                }
            }

            if (
                id == UNDERLYING_FREE_LIQ_TOKEN_ID ||
                id == BASE_FREE_LIQ_TOKEN_ID
            ) {
                bool isCallPool = id == UNDERLYING_FREE_LIQ_TOKEN_ID;
                uint256 minimum = _getMinimumAmount(l, isCallPool);

                if (from != address(0)) {
                    uint256 balance = _balanceOf(from, id);

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

                    if (to != address(0)) {
                        _subUserTVL(l, from, isCallPool, amounts[i]);
                        _addUserTVL(l, to, isCallPool, amounts[i]);
                    }
                }

                if (to != address(0)) {
                    uint256 balance = _balanceOf(to, id);

                    if (balance <= minimum && balance + amount > minimum) {
                        l.addUnderwriter(to, isCallPool);
                    }
                }
            }

            // Update userTVL on SHORT options transfers
            (
                PoolStorage.TokenType tokenType,
                ,
                int128 strike64x64
            ) = PoolStorage.parseTokenId(id);

            if (
                (from != address(0) && to != address(0)) &&
                (tokenType == PoolStorage.TokenType.SHORT_CALL ||
                    tokenType == PoolStorage.TokenType.SHORT_PUT)
            ) {
                bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL;
                uint256 collateral = isCall
                    ? amount
                    : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(amount));

                _subUserTVL(l, from, isCall, collateral);
                _addUserTVL(l, to, isCall, collateral);
            }
        }
    }
}
