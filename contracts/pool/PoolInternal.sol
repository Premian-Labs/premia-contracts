// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC173} from "@solidstate/contracts/access/IERC173.sol";
import {OwnableStorage} from "@solidstate/contracts/access/OwnableStorage.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {ERC1155EnumerableInternal, ERC1155EnumerableStorage, EnumerableSet} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
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

    struct Interval {
        uint256 contractSize;
        uint256 tokenAmount;
        uint256 payment;
        uint256 apyFee;
    }

    address internal immutable WETH_ADDRESS;
    address internal immutable PREMIA_MINING_ADDRESS;
    address internal immutable FEE_RECEIVER_ADDRESS;
    address internal immutable FEE_DISCOUNT_ADDRESS;
    address internal immutable IVOL_ORACLE_ADDRESS;

    int128 internal immutable FEE_PREMIUM_64x64;
    int128 internal immutable FEE_APY_64x64;

    uint256 internal immutable UNDERLYING_FREE_LIQ_TOKEN_ID;
    uint256 internal immutable BASE_FREE_LIQ_TOKEN_ID;

    uint256 internal immutable UNDERLYING_RESERVED_LIQ_TOKEN_ID;
    uint256 internal immutable BASE_RESERVED_LIQ_TOKEN_ID;

    uint256 internal constant INVERSE_BASIS_POINT = 1e4;
    uint256 internal constant BATCHING_PERIOD = 260;

    // Minimum APY for capital locked up to underwrite options.
    // The quote will return a minimum price corresponding to this APY
    int128 internal constant MIN_APY_64x64 = 0x4ccccccccccccccd; // 0.3

    // Multiply sell quote by this constant
    int128 internal constant SELL_COEFFICIENT_64x64 = 0xb333333333333333; // 0.7

    constructor(
        address ivolOracle,
        address weth,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 feePremium64x64,
        int128 feeApy64x64
    ) {
        IVOL_ORACLE_ADDRESS = ivolOracle;
        WETH_ADDRESS = weth;
        PREMIA_MINING_ADDRESS = premiaMining;
        FEE_RECEIVER_ADDRESS = feeReceiver;
        // PremiaFeeDiscount contract address
        FEE_DISCOUNT_ADDRESS = feeDiscountAddress;
        FEE_PREMIUM_64x64 = feePremium64x64;
        FEE_APY_64x64 = feeApy64x64;

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

    function _fetchFeeDiscount64x64(address feePayer)
        internal
        view
        returns (int128 discount64x64)
    {
        if (FEE_DISCOUNT_ADDRESS != address(0)) {
            discount64x64 = ABDKMath64x64.divu(
                IFeeDiscount(FEE_DISCOUNT_ADDRESS).getDiscount(feePayer),
                INVERSE_BASIS_POINT
            );
        }
    }

    function _withdrawFees(bool isCall) internal returns (uint256 amount) {
        uint256 tokenId = _getReservedLiquidityTokenId(isCall);
        amount = _balanceOf(FEE_RECEIVER_ADDRESS, tokenId);

        if (amount > 0) {
            _burn(FEE_RECEIVER_ADDRESS, tokenId, amount);
            _pushTo(
                FEE_RECEIVER_ADDRESS,
                PoolStorage.layout().getPoolToken(isCall),
                amount
            );
            emit FeeWithdrawal(isCall, amount);
        }
    }

    /**
     * @notice calculate price of option contract
     * @param args structured quote arguments
     * @return result quote result
     */
    function _quotePurchasePrice(PoolStorage.QuoteArgsInternal memory args)
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
        result.feeCost64x64 = result.baseCost64x64.mul(FEE_PREMIUM_64x64);
        result.cLevel64x64 = cLevel64x64;
        result.slippageCoefficient64x64 = slippageCoefficient64x64;
        result.feeCost64x64 -= result.feeCost64x64.mul(
            _fetchFeeDiscount64x64(args.feePayer)
        );
    }

    function _quoteSalePrice(PoolStorage.QuoteArgsInternal memory args)
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

        int128 sellCLevel64x64;

        {
            uint256 longTokenId = PoolStorage.formatTokenId(
                PoolStorage.getTokenType(args.isCall, true),
                args.maturity,
                args.strike64x64
            );

            // Initialize to avg value, and replace by current if avg not set or current is lower
            sellCLevel64x64 = l.avgCLevel64x64[longTokenId];

            {
                (int128 currentCLevel64x64, ) = l.getRealPoolState(args.isCall);

                if (
                    sellCLevel64x64 == 0 || currentCLevel64x64 < sellCLevel64x64
                ) {
                    sellCLevel64x64 = currentCLevel64x64;
                }
            }
        }

        int128 contractSize64x64 = ABDKMath64x64Token.fromDecimals(
            args.contractSize,
            l.underlyingDecimals
        );

        baseCost64x64 = SELL_COEFFICIENT_64x64
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

        feeCost64x64 = baseCost64x64.mul(FEE_PREMIUM_64x64);

        feeCost64x64 -= feeCost64x64.mul(_fetchFeeDiscount64x64(args.feePayer));
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
        (PoolStorage.TokenType tokenType, , ) = PoolStorage.parseTokenId(
            shortTokenId
        );
        bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL;

        uint256 length = accounts.length();

        for (uint256 i = 0; i < length; i++) {
            address lp = accounts.at(i);

            if (l.isBuybackEnabled[lp][isCall]) {
                totalLiquidity += _balanceOf(lp, shortTokenId);
            }
        }
    }

    /**
     * @notice burn corresponding long and short option tokens
     * @param l storage layout struct
     * @param account holder of tokens to annihilate
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param isCall true for call, false for put
     * @param contractSize quantity of option contract tokens to annihilate
     * @return collateralFreed amount of collateral freed, including APY fee rebate
     */
    function _annihilate(
        PoolStorage.Layout storage l,
        address account,
        uint64 maturity,
        int128 strike64x64,
        bool isCall,
        uint256 contractSize
    ) internal returns (uint256 collateralFreed) {
        uint256 longTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, true),
            maturity,
            strike64x64
        );
        uint256 shortTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        uint256 tokenAmount = l.contractSizeToBaseTokenAmount(
            contractSize,
            strike64x64,
            isCall
        );

        // calculate unconsumed APY fee so that it may be refunded

        uint256 intervalApyFee = _calculateApyFee(
            l,
            shortTokenId,
            tokenAmount,
            maturity
        );

        _burn(account, longTokenId, contractSize);

        uint256 rebate = _fulfillApyFee(
            l,
            account,
            shortTokenId,
            contractSize,
            intervalApyFee,
            isCall
        );

        _burn(account, shortTokenId, contractSize);

        collateralFreed = tokenAmount + rebate + intervalApyFee;

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

        _processPendingDeposits(l, isCallPool);

        l.depositedAt[msg.sender][isCallPool] = block.timestamp;
        _addUserTVL(l, msg.sender, isCallPool, amount);
        _pullFrom(l, msg.sender, amount, isCallPool, creditMessageValue);

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
            uint256 tokenAmount = l.contractSizeToBaseTokenAmount(
                contractSize,
                strike64x64,
                isCall
            );

            uint256 freeLiquidityTokenId = _getFreeLiquidityTokenId(isCall);

            require(
                tokenAmount <=
                    _totalSupply(freeLiquidityTokenId) -
                        l.totalPendingDeposits(isCall) -
                        (_balanceOf(account, freeLiquidityTokenId) -
                            l.pendingDepositsOf(account, isCall)),
                "insuf liq"
            );
        }

        PoolStorage.QuoteResultInternal memory quote = _quotePurchasePrice(
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
            PoolStorage.getTokenType(isCall, true),
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
            maturity,
            strike64x64,
            contractSize,
            baseCost,
            isCall
        );
        int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

        _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCall);

        // mint reserved liquidity tokens for fee receiver

        _processAvailableFunds(
            FEE_RECEIVER_ADDRESS,
            feeCost,
            isCall,
            true,
            false
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
     * @return netCollateralFreed quantity of liquidity freed
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
            uint256 netCollateralFreed
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

        uint256 totalCollateralFreed = _annihilate(
            l,
            account,
            maturity,
            strike64x64,
            isCall,
            contractSize
        );

        netCollateralFreed = totalCollateralFreed - baseCost - feeCost;
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

        if (onlyExpired) {
            // burn long option tokens from multiple holders
            // transfer profit to and emit Exercise event for each holder in loop

            _burnLongTokenLoop(
                contractSize,
                exerciseValue,
                longTokenId,
                isCall
            );
        } else {
            // burn long option tokens from sender

            _burnLongTokenInterval(
                holder,
                longTokenId,
                contractSize,
                exerciseValue,
                isCall
            );
        }

        // burn short option tokens from multiple underwriters

        _burnShortTokenLoop(
            l,
            maturity,
            strike64x64,
            contractSize,
            exerciseValue,
            isCall,
            false
        );
    }

    function _calculateExerciseValue(
        PoolStorage.Layout storage l,
        uint256 contractSize,
        int128 spot64x64,
        int128 strike64x64,
        bool isCall
    ) internal view returns (uint256 exerciseValue) {
        // calculate exercise value if option is in-the-money

        if (isCall) {
            if (spot64x64 > strike64x64) {
                exerciseValue = spot64x64.sub(strike64x64).div(spot64x64).mulu(
                    contractSize
                );
            }
        } else {
            if (spot64x64 < strike64x64) {
                exerciseValue = l.contractSizeToBaseTokenAmount(
                    contractSize,
                    strike64x64.sub(spot64x64),
                    false
                );
            }
        }
    }

    function _mintShortTokenLoop(
        PoolStorage.Layout storage l,
        address buyer,
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        uint256 premium,
        bool isCall
    ) internal {
        uint256 shortTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        uint256 tokenAmount = l.contractSizeToBaseTokenAmount(
            contractSize,
            strike64x64,
            isCall
        );

        // calculate anticipated APY fee so that it may be reserved

        uint256 apyFee = _calculateApyFee(
            l,
            shortTokenId,
            tokenAmount,
            maturity
        );

        while (tokenAmount > 0) {
            address underwriter = l.liquidityQueueAscending[isCall][address(0)];

            uint256 balance = _balanceOf(
                underwriter,
                _getFreeLiquidityTokenId(isCall)
            );

            // if underwriter is in process of divestment, remove from queue

            if (!l.getReinvestmentStatus(underwriter, isCall)) {
                _burn(underwriter, _getFreeLiquidityTokenId(isCall), balance);
                _processAvailableFunds(
                    underwriter,
                    balance,
                    isCall,
                    true,
                    false
                );
                _subUserTVL(l, underwriter, isCall, balance);
                continue;
            }

            // if underwriter has insufficient liquidity, remove from queue

            if (balance < l.getMinimumAmount(isCall)) {
                l.removeUnderwriter(underwriter, isCall);
                continue;
            }

            // move interval to end of queue if underwriter is buyer

            if (underwriter == buyer) {
                l.removeUnderwriter(underwriter, isCall);
                l.addUnderwriter(underwriter, isCall);
                continue;
            }

            balance -= l.pendingDepositsOf(underwriter, isCall);

            Interval memory interval;

            // amount of liquidity provided by underwriter, accounting for reinvested premium
            interval.tokenAmount =
                (balance * (tokenAmount + premium - apyFee)) /
                tokenAmount;

            // skip underwriters whose liquidity is pending deposit processing

            if (interval.tokenAmount == 0) continue;

            // truncate interval if underwriter has excess liquidity available

            if (interval.tokenAmount > tokenAmount)
                interval.tokenAmount = tokenAmount;

            // calculate derived interval variables

            interval.contractSize =
                (contractSize * interval.tokenAmount) /
                tokenAmount;
            interval.payment = (premium * interval.tokenAmount) / tokenAmount;
            interval.apyFee = (apyFee * interval.tokenAmount) / tokenAmount;

            _mintShortTokenInterval(
                l,
                underwriter,
                buyer,
                shortTokenId,
                interval,
                isCall
            );

            tokenAmount -= interval.tokenAmount;
            contractSize -= interval.contractSize;
            premium -= interval.payment;
            apyFee -= interval.apyFee;
        }
    }

    function _mintShortTokenInterval(
        PoolStorage.Layout storage l,
        address underwriter,
        address longReceiver,
        uint256 shortTokenId,
        Interval memory interval,
        bool isCallPool
    ) internal {
        // track prepaid APY fees

        _reserveApyFee(l, underwriter, shortTokenId, interval.apyFee);

        // if payment is equal to collateral amount plus APY fee, this is a manual underwrite

        bool isManualUnderwrite = interval.payment ==
            interval.tokenAmount + interval.apyFee;

        if (!isManualUnderwrite) {
            // burn free liquidity tokens from underwriter
            _burn(
                underwriter,
                _getFreeLiquidityTokenId(isCallPool),
                interval.tokenAmount + interval.apyFee - interval.payment
            );
        }

        // mint short option tokens for underwriter
        _mint(underwriter, shortTokenId, interval.contractSize);

        _addUserTVL(
            l,
            underwriter,
            isCallPool,
            interval.payment - interval.apyFee
        );

        emit Underwrite(
            underwriter,
            longReceiver,
            shortTokenId,
            interval.contractSize,
            isManualUnderwrite ? 0 : interval.payment,
            isManualUnderwrite
        );
    }

    function _burnLongTokenLoop(
        uint256 contractSize,
        uint256 exerciseValue,
        uint256 longTokenId,
        bool isCallPool
    ) internal {
        EnumerableSet.AddressSet storage holders = ERC1155EnumerableStorage
            .layout()
            .accountsByToken[longTokenId];

        while (contractSize > 0) {
            address longTokenHolder = holders.at(holders.length() - 1);

            uint256 intervalContractSize = _balanceOf(
                longTokenHolder,
                longTokenId
            );

            // truncate interval if holder has excess long position size

            if (intervalContractSize > contractSize)
                intervalContractSize = contractSize;

            uint256 intervalExerciseValue = (exerciseValue *
                intervalContractSize) / contractSize;

            _burnLongTokenInterval(
                longTokenHolder,
                longTokenId,
                intervalContractSize,
                intervalExerciseValue,
                isCallPool
            );

            contractSize -= intervalContractSize;
            exerciseValue -= intervalExerciseValue;
        }
    }

    function _burnLongTokenInterval(
        address holder,
        uint256 longTokenId,
        uint256 contractSize,
        uint256 exerciseValue,
        bool isCallPool
    ) internal {
        _burn(holder, longTokenId, contractSize);

        if (exerciseValue > 0) {
            _processAvailableFunds(
                holder,
                exerciseValue,
                isCallPool,
                true,
                true
            );
        }

        emit Exercise(holder, longTokenId, contractSize, exerciseValue, 0);
    }

    function _burnShortTokenLoop(
        PoolStorage.Layout storage l,
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        uint256 payment,
        bool isCall,
        bool onlyBuybackLiquidity
    ) internal {
        uint256 shortTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        uint256 tokenAmount = l.contractSizeToBaseTokenAmount(
            contractSize,
            strike64x64,
            isCall
        );

        // calculate unconsumed APY fee so that it may be refunded

        uint256 apyFee = _calculateApyFee(
            l,
            shortTokenId,
            tokenAmount,
            maturity
        );

        EnumerableSet.AddressSet storage underwriters = ERC1155EnumerableStorage
            .layout()
            .accountsByToken[shortTokenId];

        uint256 index = underwriters.length();

        while (contractSize > 0) {
            address underwriter = underwriters.at(--index);

            // skip underwriters who do not provide buyback liqudity, if applicable

            if (
                onlyBuybackLiquidity && !l.isBuybackEnabled[underwriter][isCall]
            ) continue;

            Interval memory interval;

            // amount of liquidity provided by underwriter
            interval.contractSize = _balanceOf(underwriter, shortTokenId);

            // truncate interval if underwriter has excess short position size

            if (interval.contractSize > contractSize)
                interval.contractSize = contractSize;

            // calculate derived interval variables

            interval.tokenAmount =
                (tokenAmount * interval.contractSize) /
                contractSize;
            interval.payment = (payment * interval.contractSize) / contractSize;
            interval.apyFee = (apyFee * interval.contractSize) / contractSize;

            _burnShortTokenInterval(
                l,
                underwriter,
                shortTokenId,
                interval,
                isCall,
                onlyBuybackLiquidity
            );

            contractSize -= interval.contractSize;
            tokenAmount -= interval.tokenAmount;
            payment -= interval.payment;
            apyFee -= interval.apyFee;
        }
    }

    function _burnShortTokenInterval(
        PoolStorage.Layout storage l,
        address underwriter,
        uint256 shortTokenId,
        Interval memory interval,
        bool isCallPool,
        bool isSale
    ) internal {
        // track prepaid APY fees

        uint256 refundWithRebate = interval.apyFee +
            _fulfillApyFee(
                l,
                underwriter,
                shortTokenId,
                interval.contractSize,
                interval.apyFee,
                isCallPool
            );

        // burn short option tokens from underwriter
        _burn(underwriter, shortTokenId, interval.contractSize);

        bool divest = !l.getReinvestmentStatus(underwriter, isCallPool);

        _processAvailableFunds(
            underwriter,
            interval.tokenAmount - interval.payment + refundWithRebate,
            isCallPool,
            divest,
            false
        );

        if (divest) {
            _subUserTVL(l, underwriter, isCallPool, interval.tokenAmount);
        } else {
            if (refundWithRebate > interval.payment) {
                _addUserTVL(
                    l,
                    underwriter,
                    isCallPool,
                    refundWithRebate - interval.payment
                );
            } else if (interval.payment > refundWithRebate) {
                _subUserTVL(
                    l,
                    underwriter,
                    isCallPool,
                    interval.payment - refundWithRebate
                );
            }
        }

        if (isSale) {
            emit AssignSale(
                underwriter,
                shortTokenId,
                interval.tokenAmount - interval.payment,
                interval.contractSize
            );
        } else {
            emit AssignExercise(
                underwriter,
                shortTokenId,
                interval.tokenAmount - interval.payment,
                interval.contractSize,
                0
            );
        }
    }

    function _calculateApyFee(
        PoolStorage.Layout storage l,
        uint256 shortTokenId,
        uint256 tokenAmount,
        uint64 maturity
    ) internal view returns (uint256 apyFee) {
        if (block.timestamp < maturity) {
            int128 apyFeeRate64x64 = _totalSupply(shortTokenId) == 0
                ? FEE_APY_64x64
                : l.feeReserveRates[shortTokenId];

            apyFee = apyFeeRate64x64.mulu(
                (tokenAmount * (maturity - block.timestamp)) / (365 days)
            );
        }
    }

    function _reserveApyFee(
        PoolStorage.Layout storage l,
        address underwriter,
        uint256 shortTokenId,
        uint256 amount
    ) internal {
        l.feesReserved[underwriter][shortTokenId] += amount;

        emit APYFeeReserved(underwriter, shortTokenId, amount);
    }

    /**
     * @notice credit fee receiver with fees earned and calculate rebate for underwriter
     * @dev short tokens which have acrrued fee must not be burned or transferred until after this helper is called
     * @param l storage layout struct
     * @param underwriter holder of short position who reserved fees
     * @param shortTokenId short token id whose reserved fees to pay and rebate
     * @param intervalContractSize size of position for which to calculate accrued fees
     * @param intervalApyFee quantity of fees reserved but not yet accrued
     * @param isCallPool true for call, false for put
     */
    function _fulfillApyFee(
        PoolStorage.Layout storage l,
        address underwriter,
        uint256 shortTokenId,
        uint256 intervalContractSize,
        uint256 intervalApyFee,
        bool isCallPool
    ) internal returns (uint256 rebate) {
        if (intervalApyFee == 0) return 0;

        // calculate proportion of fees reserved corresponding to interval

        uint256 feesReserved = l.feesReserved[underwriter][shortTokenId];

        uint256 intervalFeesReserved = (feesReserved * intervalContractSize) /
            _balanceOf(underwriter, shortTokenId);

        // deduct fees for time not elapsed

        l.feesReserved[underwriter][shortTokenId] -= intervalFeesReserved;

        // apply rebate to fees accrued

        rebate = _fetchFeeDiscount64x64(underwriter).mulu(
            intervalFeesReserved - intervalApyFee
        );

        // credit fee receiver with fees paid

        uint256 intervalFeesPaid = intervalFeesReserved -
            intervalApyFee -
            rebate;

        _processAvailableFunds(
            FEE_RECEIVER_ADDRESS,
            intervalFeesPaid,
            isCallPool,
            true,
            false
        );

        emit APYFeePaid(underwriter, shortTokenId, intervalFeesPaid);
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
        PoolStorage.BatchData storage batchData = l.nextDeposits[isCall];

        if (batchData.eta == 0 || block.timestamp < batchData.eta) return;

        int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

        _setCLevel(
            l,
            oldLiquidity64x64,
            oldLiquidity64x64.add(
                ABDKMath64x64Token.fromDecimals(
                    batchData.totalPendingDeposits,
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

    function _updateCLevelAverage(
        PoolStorage.Layout storage l,
        uint256 longTokenId,
        uint256 contractSize,
        int128 cLevel64x64
    ) internal {
        int128 supply64x64 = ABDKMath64x64Token.fromDecimals(
            _totalSupply(longTokenId),
            l.underlyingDecimals
        );
        int128 contractSize64x64 = ABDKMath64x64Token.fromDecimals(
            contractSize,
            l.underlyingDecimals
        );

        l.avgCLevel64x64[longTokenId] = l
            .avgCLevel64x64[longTokenId]
            .mul(supply64x64)
            .add(cLevel64x64.mul(contractSize64x64))
            .div(supply64x64.add(contractSize64x64));
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
     * @param l storage layout struct
     * @param from address from which tokens are pulled from
     * @param amount quantity of token to transfer
     * @param isCallPool whether funds correspond to call or put pool
     * @param creditMessageValue whether to attempt to treat message value as credit
     */
    function _pullFrom(
        PoolStorage.Layout storage l,
        address from,
        uint256 amount,
        bool isCallPool,
        bool creditMessageValue
    ) internal {
        uint256 credit;

        if (creditMessageValue) {
            credit = _creditMessageValue(amount, isCallPool);
        }

        if (amount > credit) {
            credit += _creditReservedLiquidity(
                from,
                amount - credit,
                isCallPool
            );
        }

        if (amount > credit) {
            require(
                IERC20(l.getPoolToken(isCallPool)).transferFrom(
                    from,
                    address(this),
                    amount - credit
                ),
                "ERC20 transfer failed"
            );
        }
    }

    /**
     * @notice transfer or reinvest available user funds
     * @param account owner of funds
     * @param amount quantity of funds available
     * @param isCallPool whether funds correspond to call or put pool
     * @param divest whether to reserve funds or reinvest
     * @param transferOnDivest whether to transfer divested funds to owner
     */
    function _processAvailableFunds(
        address account,
        uint256 amount,
        bool isCallPool,
        bool divest,
        bool transferOnDivest
    ) internal {
        if (divest) {
            if (transferOnDivest) {
                _pushTo(
                    account,
                    PoolStorage.layout().getPoolToken(isCallPool),
                    amount
                );
            } else {
                _mint(
                    account,
                    _getReservedLiquidityTokenId(isCallPool),
                    amount
                );
            }
        } else {
            _addToDepositQueue(account, amount, isCallPool);
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
                PoolStorage.layout().getPoolToken(isCallPool) == WETH_ADDRESS,
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

    /**
     * @notice calculate credit amount from reserved liquidity
     * @param account address whose reserved liquidity to use as credit
     * @param amount total deposit quantity
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     * @return credit quantity of credit to apply
     */
    function _creditReservedLiquidity(
        address account,
        uint256 amount,
        bool isCallPool
    ) internal returns (uint256 credit) {
        uint256 reservedLiqTokenId = _getReservedLiquidityTokenId(isCallPool);

        uint256 balance = _balanceOf(account, reservedLiqTokenId);

        if (balance > 0) {
            credit = balance > amount ? amount : balance;

            _burn(account, reservedLiqTokenId, credit);
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

            if (to == address(0) && _totalSupply(id) == 0) {
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
                uint256 minimum = l.getMinimumAmount(isCallPool);

                if (from != address(0)) {
                    uint256 balance = _balanceOf(from, id);

                    if (balance > minimum && balance <= amount + minimum) {
                        require(
                            balance - l.pendingDepositsOf(from, isCallPool) >=
                                amount,
                            "Insuf balance"
                        );
                        l.removeUnderwriter(from, isCallPool);
                    }

                    if (to != address(0)) {
                        _subUserTVL(l, from, isCallPool, amount);
                        _addUserTVL(l, to, isCallPool, amount);
                    }
                }

                if (to != address(0)) {
                    uint256 balance = _balanceOf(to, id);

                    if (balance <= minimum && balance + amount >= minimum) {
                        l.addUnderwriter(to, isCallPool);
                    }
                }
            }

            // Update userTVL on SHORT options transfers
            (PoolStorage.TokenType tokenType, , ) = PoolStorage.parseTokenId(
                id
            );

            if (
                tokenType == PoolStorage.TokenType.SHORT_CALL ||
                tokenType == PoolStorage.TokenType.SHORT_PUT
            ) {
                _beforeShortTokenTransfer(l, from, to, id, amount);
            }
        }
    }

    function _beforeShortTokenTransfer(
        PoolStorage.Layout storage l,
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) private {
        // total supply has already been updated, so compare to amount rather than 0
        if (from == address(0) && _totalSupply(id) == amount) {
            l.feeReserveRates[id] = FEE_APY_64x64;
        }

        if (to == address(0) && _totalSupply(id) == 0) {
            delete l.feeReserveRates[id];
        }

        if (from != address(0) && to != address(0)) {
            (
                PoolStorage.TokenType tokenType,
                uint64 maturity,
                int128 strike64x64
            ) = PoolStorage.parseTokenId(id);

            bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL;
            uint256 collateral = l.contractSizeToBaseTokenAmount(
                amount,
                strike64x64,
                isCall
            );

            uint256 intervalApyFee = _calculateApyFee(
                l,
                id,
                collateral,
                maturity
            );

            uint256 rebate = _fulfillApyFee(
                l,
                from,
                id,
                amount,
                intervalApyFee,
                isCall
            );

            _reserveApyFee(l, to, id, intervalApyFee);

            bool divest = !l.getReinvestmentStatus(from, isCall);

            if (rebate > 0) {
                _processAvailableFunds(from, rebate, isCall, divest, false);
            }

            _subUserTVL(
                l,
                from,
                isCall,
                divest ? collateral : collateral - rebate
            );

            _addUserTVL(l, to, isCall, collateral);
        }
    }
}
