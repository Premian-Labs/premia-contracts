// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

import {IPoolIO} from "./IPoolIO.sol";
import {PoolSwap} from "./PoolSwap.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {IPremiaMining} from "../mining/IPremiaMining.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolIO is IPoolIO, PoolSwap {
    using ABDKMath64x64 for int128;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address ivolOracle,
        address weth,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 fee64x64,
        address uniswapV2Factory,
        address sushiswapFactory
    )
        PoolSwap(
            ivolOracle,
            weth,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            fee64x64,
            uniswapV2Factory,
            sushiswapFactory
        )
    {}

    /**
     * @inheritdoc IPoolIO
     */
    function setDivestmentTimestamp(uint64 timestamp, bool isCallPool)
        external
        override
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        require(
            timestamp == 0 ||
                timestamp >= l.depositedAt[msg.sender][isCallPool] + (1 days),
            "liq lock 1d"
        );

        l.divestmentTimestamps[msg.sender][isCallPool] = timestamp;
    }

    /**
     * @inheritdoc IPoolIO
     */
    function deposit(uint256 amount, bool isCallPool)
        external
        payable
        override
    {
        _deposit(amount, isCallPool, false);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function swapAndDeposit(
        uint256 amount,
        bool isCallPool,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        bool isSushi
    ) external payable override {
        // If value is passed, amountInMax must be 0, as the value wont be used
        // If amountInMax is not 0, user wants to do a swap from an ERC20, and therefore no value should be attached
        require(
            msg.value == 0 || amountInMax == 0,
            "value and amountInMax passed"
        );

        // If no amountOut has been passed, we swap the exact deposit amount specified
        if (amountOut == 0) {
            amountOut = amount;
        }

        if (msg.value > 0) {
            _swapETHForExactTokens(amountOut, path, isSushi);
        } else {
            _swapTokensForExactTokens(amountOut, amountInMax, path, isSushi);
        }

        _deposit(amount, isCallPool, true);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function withdraw(uint256 amount, bool isCallPool) public override {
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
            uint256 reservedLiquidity = _balanceOf(
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

        _subUserTVL(l, msg.sender, isCallPool, amount);
        _pushTo(msg.sender, _getPoolToken(isCallPool), amount);
        emit Withdrawal(msg.sender, isCallPool, depositedAt, amount);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function reassign(uint256 tokenId, uint256 contractSize)
        external
        override
        returns (
            uint256 baseCost,
            uint256 feeCost,
            uint256 amountOut
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        int128 newPrice64x64 = _update(l);

        (
            PoolStorage.TokenType tokenType,
            uint64 maturity,
            int128 strike64x64
        ) = PoolStorage.parseTokenId(tokenId);
        bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL ||
            tokenType == PoolStorage.TokenType.LONG_CALL;
        (baseCost, feeCost, amountOut) = _reassign(
            l,
            msg.sender,
            maturity,
            strike64x64,
            isCall,
            contractSize,
            newPrice64x64
        );

        _pushTo(msg.sender, _getPoolToken(isCall), amountOut);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function reassignBatch(
        uint256[] calldata tokenIds,
        uint256[] calldata contractSizes
    )
        public
        override
        returns (
            uint256[] memory baseCosts,
            uint256[] memory feeCosts,
            uint256 amountOutCall,
            uint256 amountOutPut
        )
    {
        require(tokenIds.length == contractSizes.length, "diff array length");

        PoolStorage.Layout storage l = PoolStorage.layout();

        int128 newPrice64x64 = _update(l);

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
                msg.sender,
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
     * @inheritdoc IPoolIO
     */
    function withdrawAllAndReassignBatch(
        bool isCallPool,
        uint256[] calldata tokenIds,
        uint256[] calldata contractSizes
    )
        external
        override
        returns (
            uint256[] memory baseCosts,
            uint256[] memory feeCosts,
            uint256 amountOutCall,
            uint256 amountOutPut
        )
    {
        uint256 balance = _balanceOf(
            msg.sender,
            _getFreeLiquidityTokenId(isCallPool)
        );

        if (balance > 0) {
            withdraw(balance, isCallPool);
        }

        (baseCosts, feeCosts, amountOutCall, amountOutPut) = reassignBatch(
            tokenIds,
            contractSizes
        );
    }

    /**
     * @inheritdoc IPoolIO
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
     * @inheritdoc IPoolIO
     */
    function annihilate(uint256 tokenId, uint256 contractSize)
        external
        override
    {
        (
            PoolStorage.TokenType tokenType,
            uint64 maturity,
            int128 strike64x64
        ) = PoolStorage.parseTokenId(tokenId);

        bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL ||
            tokenType == PoolStorage.TokenType.LONG_CALL;

        _annihilate(msg.sender, maturity, strike64x64, isCall, contractSize);

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

    /**
     * @inheritdoc IPoolIO
     */
    function claimRewards(bool isCallPool) external override {
        claimRewards(msg.sender, isCallPool);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function claimRewards(address account, bool isCallPool) public override {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 userTVL = l.userTVL[account][isCallPool];
        uint256 totalTVL = l.totalTVL[isCallPool];

        IPremiaMining(PREMIA_MINING_ADDRESS).claim(
            account,
            address(this),
            isCallPool,
            userTVL,
            userTVL,
            totalTVL
        );
    }

    /**
     * @inheritdoc IPoolIO
     */
    function updateMiningPools() external override {
        PoolStorage.Layout storage l = PoolStorage.layout();

        IPremiaMining(PREMIA_MINING_ADDRESS).updatePool(
            address(this),
            true,
            l.totalTVL[true]
        );

        IPremiaMining(PREMIA_MINING_ADDRESS).updatePool(
            address(this),
            false,
            l.totalTVL[false]
        );
    }

    /**
     * @notice deposit underlying currency, underwriting calls of that currency with respect to base currency
     * @param amount quantity of underlying currency to deposit
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     * @param skipWethDeposit if false, will not try to deposit weth from attach eth
     */
    function _deposit(
        uint256 amount,
        bool isCallPool,
        bool skipWethDeposit
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
            skipWethDeposit
        );

        _addToDepositQueue(msg.sender, amount, isCallPool);

        emit Deposit(msg.sender, isCallPool, amount);
    }
}
