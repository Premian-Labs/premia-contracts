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
        result.feeCost64x64 = result.baseCost64x64.mul(FEE_PREMIUM_64x64);
        result.cLevel64x64 = cLevel64x64;
        result.slippageCoefficient64x64 = slippageCoefficient64x64;

        result.feeCost64x64 -= result.feeCost64x64.mul(
            _fetchFeeDiscount64x64(args.feePayer)
        );
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
            PoolStorage.getTokenType(isCall, true),
            maturity,
            strike64x64
        );
        uint256 shortTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, false),
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

        uint256 cap = l.getPoolCapAmount(isCallPool);

        require(
            l.totalTVL[isCallPool] + amount <= cap,
            "pool deposit cap reached"
        );

        _processPendingDeposits(l, isCallPool);

        l.depositedAt[msg.sender][isCallPool] = block.timestamp;
        _addUserTVL(l, msg.sender, isCallPool, amount);
        _pullFrom(
            msg.sender,
            l.getPoolToken(isCallPool),
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
            uint256 tokenAmount = l.contractSizeToBaseTokenAmount(
                contractSize,
                strike64x64,
                isCall
            );

            require(
                tokenAmount <=
                    ERC1155EnumerableStorage.layout().totalSupply[
                        _getFreeLiquidityTokenId(isCall)
                    ] -
                        l.totalPendingDeposits(isCall),
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
            PoolStorage.getTokenType(isCall, true),
            maturity,
            strike64x64
        );

        uint256 shortTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, false),
            maturity,
            strike64x64
        );

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

        uint256 tokenAmount = l.contractSizeToBaseTokenAmount(
            contractSize,
            strike64x64,
            isCall
        );

        amountOut = tokenAmount - baseCost - feeCost;
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

        uint256 exerciseValue;

        // calculate exercise value if option is in-the-money

        int128 priceMoneyness64x64 = isCall
            ? spot64x64.sub(strike64x64)
            : strike64x64.sub(spot64x64);

        if (priceMoneyness64x64 > 0) {
            if (isCall) {
                exerciseValue = priceMoneyness64x64.div(spot64x64).mulu(
                    contractSize
                );
            } else {
                exerciseValue = l.contractSizeToBaseTokenAmount(
                    contractSize,
                    priceMoneyness64x64,
                    false
                );
            }
        }

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
            contractSize,
            exerciseValue,
            PoolStorage.formatTokenId(
                PoolStorage.getTokenType(isCall, false),
                maturity,
                strike64x64
            ),
            isCall
        );
    }

    function _mintShortTokenLoop(
        PoolStorage.Layout storage l,
        address buyer,
        uint256 contractSize,
        uint256 premium,
        uint256 shortTokenId,
        bool isCall
    ) internal {
        uint256 tokenAmount;
        uint256 apyFee;

        {
            (, uint64 maturity, int128 strike64x64) = PoolStorage.parseTokenId(
                shortTokenId
            );

            tokenAmount = l.contractSizeToBaseTokenAmount(
                contractSize,
                strike64x64,
                isCall
            );

            apyFee = _calculateApyFee(tokenAmount, maturity);
        }

        while (tokenAmount > 0) {
            address underwriter = l.liquidityQueueAscending[isCall][address(0)];

            Interval memory interval;

            uint256 balance = _balanceOf(
                underwriter,
                _getFreeLiquidityTokenId(isCall)
            );

            // if underwriter has insufficient liquidity, remove from queue

            if (balance < l.getMinimumAmount(isCall)) {
                l.removeUnderwriter(underwriter, isCall);
                continue;
            }

            // if underwriter is in process of divestment, remove from queue

            if (!l.getReinvestmentStatus(underwriter, isCall)) {
                _burn(underwriter, _getFreeLiquidityTokenId(isCall), balance);
                _mint(
                    underwriter,
                    _getReservedLiquidityTokenId(isCall),
                    balance
                );
                _subUserTVL(l, underwriter, isCall, balance);
                continue;
            }

            balance -= l.pendingDepositsOf(underwriter, isCall);

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
        address buyer,
        uint256 shortTokenId,
        Interval memory interval,
        bool isCallPool
    ) internal {
        // track prepaid APY fees

        l.feesReserved[underwriter][shortTokenId] += interval.apyFee;

        // burn free liquidity tokens from underwriter
        _burn(
            underwriter,
            _getFreeLiquidityTokenId(isCallPool),
            interval.tokenAmount - interval.payment + interval.apyFee
        );

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
            buyer,
            shortTokenId,
            interval.contractSize,
            interval.payment,
            false
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
            _processAvailableFunds(holder, exerciseValue, isCallPool, true);
        }

        emit Exercise(holder, longTokenId, contractSize, exerciseValue, 0);
    }

    function _burnShortTokenLoop(
        PoolStorage.Layout storage l,
        uint256 contractSize,
        uint256 exerciseValue,
        uint256 shortTokenId,
        bool isCall
    ) internal {
        uint256 tokenAmount;
        uint256 apyFee;

        {
            (, uint64 maturity, int128 strike64x64) = PoolStorage.parseTokenId(
                shortTokenId
            );

            tokenAmount = l.contractSizeToBaseTokenAmount(
                contractSize,
                strike64x64,
                isCall
            );

            if (maturity > block.timestamp) {
                apyFee = _calculateApyFee(tokenAmount, maturity);
            }
        }

        EnumerableSet.AddressSet storage underwriters = ERC1155EnumerableStorage
            .layout()
            .accountsByToken[shortTokenId];

        while (contractSize > 0) {
            address underwriter = underwriters.at(underwriters.length() - 1);

            Interval memory interval;

            // amount of liquidity provided by underwriter
            interval.contractSize = _balanceOf(underwriter, shortTokenId);

            // truncate interval if underwriter has excess short position size

            if (interval.contractSize > contractSize)
                interval.contractSize = contractSize;

            // calculate derived interval variables

            interval.payment =
                (exerciseValue * interval.contractSize) /
                contractSize;
            interval.tokenAmount =
                (tokenAmount * interval.contractSize) /
                contractSize;
            interval.apyFee = (apyFee * interval.contractSize) / contractSize;

            _burnShortTokenInterval(
                l,
                underwriter,
                shortTokenId,
                interval,
                isCall
            );

            contractSize -= interval.contractSize;
            exerciseValue -= interval.payment;
            tokenAmount -= interval.tokenAmount;
            apyFee -= interval.apyFee;
        }
    }

    function _burnShortTokenInterval(
        PoolStorage.Layout storage l,
        address underwriter,
        uint256 shortTokenId,
        Interval memory interval,
        bool isCallPool
    ) internal {
        // track prepaid APY fees

        uint256 rebate = _applyApyFeeRebate(
            l,
            underwriter,
            shortTokenId,
            interval.contractSize,
            interval.apyFee,
            isCallPool
        );

        // burn short option tokens from underwriter
        _burn(underwriter, shortTokenId, interval.contractSize);

        // mint free or reserved liquidity tokens for underwriter
        if (l.getReinvestmentStatus(underwriter, isCallPool)) {
            _addToDepositQueue(
                underwriter,
                interval.tokenAmount - interval.payment + rebate,
                isCallPool
            );

            if (rebate > interval.payment) {
                _addUserTVL(
                    l,
                    underwriter,
                    isCallPool,
                    rebate - interval.payment
                );
            } else if (interval.payment > rebate) {
                _subUserTVL(
                    l,
                    underwriter,
                    isCallPool,
                    interval.payment - rebate
                );
            }
        } else {
            _mint(
                underwriter,
                _getReservedLiquidityTokenId(isCallPool),
                interval.tokenAmount - interval.payment + rebate
            );

            _subUserTVL(
                l,
                underwriter,
                isCallPool,
                interval.tokenAmount - interval.payment
            );
        }

        emit AssignExercise(
            underwriter,
            shortTokenId,
            interval.tokenAmount - interval.payment,
            interval.contractSize,
            0
        );
    }

    function _calculateApyFee(uint256 tokenAmount, uint64 maturity)
        internal
        view
        returns (uint256 apyFee)
    {
        apyFee = FEE_APY_64x64.mulu(
            (tokenAmount * (maturity - block.timestamp)) / (365 days)
        );
    }

    function _applyApyFeeRebate(
        PoolStorage.Layout storage l,
        address underwriter,
        uint256 shortTokenId,
        uint256 intervalContractSize,
        uint256 intervalApyFee,
        bool isCallPool
    ) internal returns (uint256 rebate) {
        // calculate proportion of fees reserved corresponding to interval

        uint256 feesReserved = l.feesReserved[underwriter][shortTokenId];

        uint256 intervalFeesReserved = (feesReserved * intervalContractSize) /
            _balanceOf(underwriter, shortTokenId);

        l.feesReserved[underwriter][shortTokenId] -= intervalFeesReserved;

        // deduct fees for time not elapsed and apply rebate to fees accrued

        rebate =
            intervalApyFee +
            _fetchFeeDiscount64x64(underwriter).mulu(
                intervalFeesReserved - intervalApyFee
            );

        _processAvailableFunds(
            FEE_RECEIVER_ADDRESS,
            intervalFeesReserved - rebate,
            isCallPool,
            true
        );
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
     * @notice transfer or reinvest available user funds
     * @param account owner of funds
     * @param amount quantity of funds available
     * @param isCallPool whether funds correspond to call or put pool
     * @param divest whether to transfer funds to owner or reinvest
     */
    function _processAvailableFunds(
        address account,
        uint256 amount,
        bool isCallPool,
        bool divest
    ) internal {
        if (divest) {
            _pushTo(
                account,
                PoolStorage.layout().getPoolToken(isCallPool),
                amount
            );
        } else {
            // TODO: redeposit
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
                uint256 collateral = l.contractSizeToBaseTokenAmount(
                    amount,
                    strike64x64,
                    isCall
                );

                _subUserTVL(l, from, isCall, collateral);
                _addUserTVL(l, to, isCall, collateral);
            }
        }
    }
}
