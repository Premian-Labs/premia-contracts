// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {PoolStorage} from "./PoolStorage.sol";

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {IPool} from "./IPool.sol";
import {PoolInternal} from "./PoolInternal.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is IPool, PoolInternal {
    using ABDKMath64x64 for int128;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address weth,
        address feeReceiver,
        address feeDiscountAddress,
        int128 fee64x64,
        uint256 batchingPeriod
    )
        PoolInternal(
            weth,
            feeReceiver,
            feeDiscountAddress,
            fee64x64,
            batchingPeriod
        )
    {}

    /**
     * @notice calculate price of option contract
     * @param feePayer address of the fee payer
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     * @return baseCost64x64 64x64 fixed point representation of option cost denominated in underlying currency (without fee)
     * @return feeCost64x64 64x64 fixed point representation of option fee cost denominated in underlying currency for call, or base currency for put
     * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
     * @return slippageCoefficient64x64 64x64 fixed point representation of slippage coefficient for given order size
     */
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
        )
    {
        int128 spot64x64;
        int128 emaVarianceAnnualized64x64;

        PoolStorage.Layout storage l = PoolStorage.layout();
        if (l.updatedAt != block.timestamp) {
            (spot64x64, , , , , emaVarianceAnnualized64x64) = _calculateUpdate(
                PoolStorage.layout()
            );
        } else {
            spot64x64 = l.getPriceUpdate(block.timestamp);
            emaVarianceAnnualized64x64 = l.emaVarianceAnnualized64x64;
        }

        (
            baseCost64x64,
            feeCost64x64,
            cLevel64x64,
            slippageCoefficient64x64
        ) = _quote(
            PoolStorage.QuoteArgsInternal(
                feePayer,
                maturity,
                strike64x64,
                spot64x64,
                emaVarianceAnnualized64x64,
                contractSize,
                isCall
            )
        );
    }

    /**
     * @notice set timestamp after which reinvestment is disabled
     * @param timestamp timestamp to begin divestment
     */
    function setDivestmentTimestamp(uint64 timestamp) external {
        PoolStorage.Layout storage l = PoolStorage.layout();
        l.divestmentTimestamps[msg.sender] = timestamp;
    }

    /**
     * @notice purchase call option
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put,
     * @param maxCost maximum acceptable cost after accounting for slippage
     * @return baseCost quantity of tokens required to purchase long position
     * @return feeCost quantity of tokens required to pay fees
     */
    function purchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost
    ) external payable returns (uint256 baseCost, uint256 feeCost) {
        // TODO: specify payment currency

        PoolStorage.Layout storage l = PoolStorage.layout();

        require(maturity >= block.timestamp + (1 days), "exp < 1 day");
        require(maturity < block.timestamp + (29 days), "exp > 28 days");
        require(maturity % (1 days) == 0, "exp not end UTC day");

        (int128 newPrice64x64, ) = _update(l);

        require(strike64x64 <= (newPrice64x64 * 3) / 2, "strike > 1.5x spot");
        require(strike64x64 >= (newPrice64x64 * 3) / 4, "strike < 0.75x spot");

        (baseCost, feeCost) = _purchase(
            l,
            maturity,
            strike64x64,
            isCall,
            contractSize,
            newPrice64x64
        );

        require(baseCost + feeCost <= maxCost, "excess slipp");

        _pullFrom(msg.sender, _getPoolToken(isCall), baseCost + feeCost);
    }

    /**
     * @notice write call option without using liquidity from the pool on behalf of another address
     * @param underwriter underwriter of the option from who collateral will be deposited
     * @param longReceiver address who will receive the long token (Can be the underwriter)
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize quantity of option contract tokens to exercise
     * @param isCall whether this is a call or a put
     * @return longTokenId token id of the long call
     * @return shortTokenId token id of the short call
     */
    function writeFrom(
        address underwriter,
        address longReceiver,
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall
    ) external payable returns (uint256 longTokenId, uint256 shortTokenId) {
        require(
            msg.sender == underwriter ||
                isApprovedForAll(underwriter, msg.sender),
            "not approved"
        );

        address token = _getPoolToken(isCall);

        uint256 tokenAmount = isCall
            ? contractSize
            : PoolStorage.layout().fromUnderlyingToBaseDecimals(
                strike64x64.mulu(contractSize)
            );

        _pullFrom(underwriter, token, tokenAmount);

        longTokenId = PoolStorage.formatTokenId(
            _getTokenType(isCall, true),
            maturity,
            strike64x64
        );
        shortTokenId = PoolStorage.formatTokenId(
            _getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        // mint long option token for underwriter (ERC1155)
        _mint(longReceiver, longTokenId, contractSize, "");
        // mint short option token for underwriter (ERC1155)
        _mint(underwriter, shortTokenId, contractSize, "");

        emit Underwrite(
            underwriter,
            longReceiver,
            shortTokenId,
            contractSize,
            0,
            true
        );
    }

    /**
     * @notice deposit underlying currency, underwriting calls of that currency with respect to base currency
     * @param amount quantity of underlying currency to deposit
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     */
    function deposit(uint256 amount, bool isCallPool) external payable {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _processPendingDeposits(l, isCallPool);

        l.depositedAt[msg.sender][isCallPool] = block.timestamp;
        _pullFrom(msg.sender, _getPoolToken(isCallPool), amount);

        _addToDepositQueue(msg.sender, amount, isCallPool);

        emit Deposit(msg.sender, isCallPool, amount);
    }

    /**
     * @notice redeem pool share tokens for underlying asset
     * @param amount quantity of share tokens to redeem
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     */
    function withdraw(uint256 amount, bool isCallPool) public {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 toWithdraw = amount;

        _processPendingDeposits(l, isCallPool);

        uint256 depositedAt = l.depositedAt[msg.sender][isCallPool];

        require(depositedAt + (1 days) < block.timestamp, "liq lock 1d");

        int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCallPool);

        {
            uint256 reservedLiqTokenId = _getReservedLiquidityTokenId(
                isCallPool
            );
            uint256 reservedLiquidity = balanceOf(
                msg.sender,
                reservedLiqTokenId
            );

            if (reservedLiquidity > 0) {
                uint256 reservedLiqToWithdraw;
                if (reservedLiquidity < toWithdraw) {
                    reservedLiqToWithdraw = reservedLiquidity;
                } else {
                    reservedLiqToWithdraw = toWithdraw;
                }

                toWithdraw -= reservedLiqToWithdraw;
                // burn reserved liquidity tokens from sender
                _burn(msg.sender, reservedLiqTokenId, reservedLiqToWithdraw);
            }
        }

        if (toWithdraw > 0) {
            // burn free liquidity tokens from sender
            _burn(msg.sender, _getFreeLiquidityTokenId(isCallPool), toWithdraw);

            int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(
                isCallPool
            );
            _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCallPool);
        }

        _pushTo(msg.sender, _getPoolToken(isCallPool), amount);
        emit Withdrawal(msg.sender, isCallPool, depositedAt, amount);
    }

    /**
     * @notice reassign short position to new liquidity provider
     * @param tokenId ERC1155 token id (long or short)
     * @param contractSize quantity of option contract tokens to reassign
     * @return baseCost quantity of tokens required to reassign short position
     * @return feeCost quantity of tokens required to pay fees
     * @return amountOut TODO
     */
    function reassign(uint256 tokenId, uint256 contractSize)
        external
        returns (
            uint256 baseCost,
            uint256 feeCost,
            uint256 amountOut
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        (int128 newPrice64x64, ) = _update(l);

        (
            PoolStorage.TokenType tokenType,
            uint64 maturity,
            int128 strike64x64
        ) = PoolStorage.parseTokenId(tokenId);
        bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL ||
            tokenType == PoolStorage.TokenType.LONG_CALL;
        (baseCost, feeCost, amountOut) = _reassign(
            l,
            maturity,
            strike64x64,
            isCall,
            contractSize,
            newPrice64x64
        );

        _pushTo(msg.sender, _getPoolToken(isCall), amountOut);
    }

    /**
     * @notice TODO
     */
    function reassignBatch(
        uint256[] calldata tokenIds,
        uint256[] calldata contractSizes
    )
        public
        returns (
            uint256[] memory baseCosts,
            uint256[] memory feeCosts,
            uint256 amountOutCall,
            uint256 amountOutPut
        )
    {
        require(tokenIds.length == contractSizes.length, "TODO");

        PoolStorage.Layout storage l = PoolStorage.layout();

        (int128 newPrice64x64, ) = _update(l);

        baseCosts = new uint256[](tokenIds.length);
        feeCosts = new uint256[](tokenIds.length);

        for (uint256 i; i < tokenIds.length; i++) {
            (
                PoolStorage.TokenType tokenType,
                uint64 maturity,
                int128 strike64x64
            ) = PoolStorage.parseTokenId(tokenIds[i]);
            bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL ||
                tokenType == PoolStorage.TokenType.LONG_CALL;
            uint256 amountOut;
            uint256 contractSize = contractSizes[i];
            (baseCosts[i], feeCosts[i], amountOut) = _reassign(
                l,
                maturity,
                strike64x64,
                isCall,
                contractSize,
                newPrice64x64
            );

            if (isCall) {
                amountOutCall += amountOut;
            } else {
                amountOutPut += amountOut;
            }
        }

        _pushTo(msg.sender, _getPoolToken(true), amountOutCall);

        _pushTo(msg.sender, _getPoolToken(false), amountOutPut);
    }

    /**
     * @notice TODO
     */
    function withdrawAllAndReassignBatch(
        bool isCallPool,
        uint256[] calldata ids,
        uint256[] calldata contractSizes
    )
        external
        returns (
            uint256[] memory baseCosts,
            uint256[] memory feeCosts,
            uint256 amountOutCall,
            uint256 amountOutPut
        )
    {
        uint256 balance = balanceOf(
            msg.sender,
            _getFreeLiquidityTokenId(isCallPool)
        );

        if (balance > 0) {
            withdraw(balance, isCallPool);
        }

        (baseCosts, feeCosts, amountOutCall, amountOutPut) = reassignBatch(
            ids,
            contractSizes
        );
    }

    /**
     * @notice Update pool data
     */
    function update() external returns (int128 newEmaVarianceAnnualized64x64) {
        (, newEmaVarianceAnnualized64x64) = _update(PoolStorage.layout());
    }

    /**
     * @notice TODO
     */
    function withdrawFees()
        external
        override
        returns (uint256 amountOutCall, uint256 amountOutPut)
    {
        amountOutCall = _withdrawFees(true);
        amountOutPut = _withdrawFees(false);
        _pushTo(FEE_RECEIVER_ADDRESS, _getPoolToken(true), amountOutCall);
        _pushTo(FEE_RECEIVER_ADDRESS, _getPoolToken(false), amountOutPut);
    }

    /**
     * @notice Burn long and short tokens to withdraw collateral
     * @param tokenId ERC1155 token id (long or short)
     * @param contractSize quantity of option contract tokens to annihilate
     */
    function annihilate(uint256 tokenId, uint256 contractSize) external {
        (
            PoolStorage.TokenType tokenType,
            uint64 maturity,
            int128 strike64x64
        ) = PoolStorage.parseTokenId(tokenId);
        bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL ||
            tokenType == PoolStorage.TokenType.LONG_CALL;
        _annihilate(maturity, strike64x64, isCall, contractSize);

        _pushTo(
            msg.sender,
            _getPoolToken(isCall),
            isCall
                ? contractSize
                : PoolStorage.layout().fromUnderlyingToBaseDecimals(
                    strike64x64.mulu(contractSize)
                )
        );
    }
}
