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
        int128 feePremium64x64,
        address uniswapV2Factory,
        address sushiswapFactory,
        uint256 uniswapV2InitHash,
        uint256 sushiswapInitHash
    )
        PoolSwap(
            ivolOracle,
            weth,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            feePremium64x64,
            uniswapV2Factory,
            sushiswapFactory,
            uniswapV2InitHash,
            sushiswapInitHash
        )
    {}

    /**
     * @inheritdoc IPoolIO
     */
    function setDivestmentTimestamp(uint64 timestamp, bool isCallPool)
        external
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
    function deposit(uint256 amount, bool isCallPool) external payable {
        _deposit(amount, isCallPool, true);
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
    ) external payable {
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

        _deposit(amount, isCallPool, false);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function withdraw(uint256 amount, bool isCallPool) public {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 toWithdraw = amount;

        _processPendingDeposits(l, isCallPool);

        uint256 depositedAt = l.depositedAt[msg.sender][isCallPool];

        require(depositedAt + (1 days) < block.timestamp, "liq lock 1d");

        int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCallPool);

        uint256 reservedLiqToWithdraw;

        {
            uint256 reservedLiqTokenId = _getReservedLiquidityTokenId(
                isCallPool
            );
            uint256 reservedLiquidity = _balanceOf(
                msg.sender,
                reservedLiqTokenId
            );

            if (reservedLiquidity > 0) {
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

        _subUserTVL(l, msg.sender, isCallPool, amount - reservedLiqToWithdraw);
        _processAvailableFunds(msg.sender, amount, isCallPool, true, true);
        emit Withdrawal(msg.sender, isCallPool, depositedAt, amount);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function reassign(
        uint256 tokenId,
        uint256 contractSize,
        bool divest
    )
        external
        returns (
            uint256 baseCost,
            uint256 feeCost,
            uint256 amountOut
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        int128 newPrice64x64 = _update(l);

        uint64 maturity;
        int128 strike64x64;
        bool isCall;

        {
            PoolStorage.TokenType tokenType;
            (tokenType, maturity, strike64x64) = PoolStorage.parseTokenId(
                tokenId
            );

            isCall =
                tokenType == PoolStorage.TokenType.SHORT_CALL ||
                tokenType == PoolStorage.TokenType.LONG_CALL;
        }

        (baseCost, feeCost, amountOut) = _reassign(
            l,
            msg.sender,
            maturity,
            strike64x64,
            isCall,
            contractSize,
            newPrice64x64
        );

        _processAvailableFunds(msg.sender, amountOut, isCall, divest, true);

        _subUserTVL(
            l,
            msg.sender,
            isCall,
            divest ? baseCost + feeCost + amountOut : baseCost + feeCost
        );
    }

    /**
     * @inheritdoc IPoolIO
     */
    function reassignBatch(
        uint256[] calldata tokenIds,
        uint256[] calldata contractSizes,
        bool divest
    )
        public
        returns (
            uint256[] memory baseCosts,
            uint256[] memory feeCosts,
            uint256 amountOutCall,
            uint256 amountOutPut
        )
    {
        require(tokenIds.length == contractSizes.length, "diff array length");

        int128 newPrice64x64 = _update(PoolStorage.layout());

        baseCosts = new uint256[](tokenIds.length);
        feeCosts = new uint256[](tokenIds.length);
        bool[] memory isCallToken = new bool[](tokenIds.length);

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

            isCallToken[i] = isCall;

            (baseCosts[i], feeCosts[i], amountOut) = _reassign(
                PoolStorage.layout(),
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

        if (amountOutCall > 0) {
            uint256 reassignmentCost;

            for (uint256 i; i < tokenIds.length; i++) {
                if (isCallToken[i] == false) continue;

                reassignmentCost += baseCosts[i];
                reassignmentCost += feeCosts[i];
            }

            _processAvailableFunds(
                msg.sender,
                amountOutCall,
                true,
                divest,
                true
            );

            _subUserTVL(
                PoolStorage.layout(),
                msg.sender,
                true,
                divest ? reassignmentCost + amountOutCall : reassignmentCost
            );
        }

        if (amountOutPut > 0) {
            uint256 reassignmentCost;

            for (uint256 i; i < tokenIds.length; i++) {
                if (isCallToken[i] == true) continue;

                reassignmentCost += baseCosts[i];
                reassignmentCost += feeCosts[i];
            }

            _processAvailableFunds(
                msg.sender,
                amountOutPut,
                false,
                divest,
                true
            );

            _subUserTVL(
                PoolStorage.layout(),
                msg.sender,
                false,
                divest ? reassignmentCost + amountOutPut : reassignmentCost
            );
        }
    }

    /**
     * @inheritdoc IPoolIO
     */
    function withdrawFees()
        external
        returns (uint256 amountOutCall, uint256 amountOutPut)
    {
        amountOutCall = _withdrawFees(true);
        amountOutPut = _withdrawFees(false);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function annihilate(
        uint256 tokenId,
        uint256 contractSize,
        bool divest
    ) external {
        (
            PoolStorage.TokenType tokenType,
            uint64 maturity,
            int128 strike64x64
        ) = PoolStorage.parseTokenId(tokenId);

        bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL ||
            tokenType == PoolStorage.TokenType.LONG_CALL;

        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 collateralFreed = _annihilate(
            l,
            msg.sender,
            maturity,
            strike64x64,
            isCall,
            contractSize
        );

        uint256 tokenAmount = l.contractSizeToBaseTokenAmount(
            contractSize,
            strike64x64,
            isCall
        );

        _processAvailableFunds(
            msg.sender,
            collateralFreed,
            isCall,
            divest,
            true
        );

        _subUserTVL(
            l,
            msg.sender,
            isCall,
            divest ? tokenAmount : collateralFreed - tokenAmount
        );
    }

    /**
     * @inheritdoc IPoolIO
     */
    function claimRewards(bool isCallPool) external {
        claimRewards(msg.sender, isCallPool);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function claimRewards(address account, bool isCallPool) public {
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
    function updateMiningPools() external {
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
}
