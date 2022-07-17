// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {ABDKMath64x64Token} from "@solidstate/abdk-math-extensions/contracts/ABDKMath64x64Token.sol";

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

    struct ReassignBatchArgs {
        uint256[] tokenIds;
        uint256[] contractSizes;
        bool divest;
        int128 newPrice64x64;
        int128 utilizationCall64x64;
        int128 utilizationPut64x64;
    }

    struct ReassignBatchResult {
        uint256[] baseCosts;
        uint256[] feeCosts;
        uint256 amountOutCall;
        uint256 amountOutPut;
    }

    constructor(
        address ivolOracle,
        address wrappedNativeToken,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 feePremium64x64,
        address exchangeProxy
    )
        PoolSwap(
            ivolOracle,
            wrappedNativeToken,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            feePremium64x64,
            exchangeProxy
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
        PoolStorage.Layout storage l = PoolStorage.layout();
        _pullFrom(l, msg.sender, amount, isCallPool, true);
        _deposit(l, amount, isCallPool);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function swapAndDeposit(
        address tokenIn,
        uint256 amountInMax,
        uint256 amountOutMin,
        address callee,
        bytes calldata data,
        address refundAddress,
        bool isCallPool
    ) external payable {
        PoolStorage.Layout storage l = PoolStorage.layout();

        address tokenOut = l.getPoolToken(isCallPool);

        uint256 creditAmount = _swapForPoolTokens(
            tokenIn,
            tokenOut,
            amountInMax,
            amountOutMin,
            callee,
            data,
            refundAddress
        );

        _deposit(l, creditAmount, isCallPool);
    }

    /**
     * @inheritdoc IPoolIO
     */
    function withdraw(uint256 amount, bool isCallPool) public {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 toWithdraw = amount;
        int128 utilization64x64 = l.getUtilization64x64(isCallPool);

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

        _subUserTVL(
            l,
            msg.sender,
            isCallPool,
            amount - reservedLiqToWithdraw,
            utilization64x64
        );
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
        bool isCall;
        int128 utilization64x64;

        {
            int128 newPrice64x64 = _update(PoolStorage.layout());
            uint64 maturity;
            int128 strike64x64;

            {
                PoolStorage.TokenType tokenType;
                (tokenType, maturity, strike64x64) = PoolStorage.parseTokenId(
                    tokenId
                );

                isCall =
                    tokenType == PoolStorage.TokenType.SHORT_CALL ||
                    tokenType == PoolStorage.TokenType.LONG_CALL;
            }

            utilization64x64 = PoolStorage.layout().getUtilization64x64(isCall);

            (baseCost, feeCost, amountOut) = _reassign(
                PoolStorage.layout(),
                msg.sender,
                maturity,
                strike64x64,
                isCall,
                contractSize,
                newPrice64x64
            );
        }

        _processAvailableFunds(msg.sender, amountOut, isCall, divest, true);

        _subUserTVL(
            PoolStorage.layout(),
            msg.sender,
            isCall,
            divest ? baseCost + feeCost + amountOut : baseCost + feeCost,
            utilization64x64
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

        int128 utilizationCall64x64 = PoolStorage.layout().getUtilization64x64(
            true
        );
        int128 utilizationPut64x64 = PoolStorage.layout().getUtilization64x64(
            false
        );

        ReassignBatchResult memory result = _reassignBatch(
            ReassignBatchArgs(
                tokenIds,
                contractSizes,
                divest,
                newPrice64x64,
                utilizationCall64x64,
                utilizationPut64x64
            )
        );

        return (
            result.baseCosts,
            result.feeCosts,
            result.amountOutCall,
            result.amountOutPut
        );
    }

    function _reassignBatch(ReassignBatchArgs memory args)
        internal
        returns (ReassignBatchResult memory result)
    {
        result.baseCosts = new uint256[](args.tokenIds.length);
        result.feeCosts = new uint256[](args.tokenIds.length);
        bool[] memory isCallToken = new bool[](args.tokenIds.length);

        for (uint256 i; i < args.tokenIds.length; i++) {
            (
                PoolStorage.TokenType tokenType,
                uint64 maturity,
                int128 strike64x64
            ) = PoolStorage.parseTokenId(args.tokenIds[i]);
            bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL ||
                tokenType == PoolStorage.TokenType.LONG_CALL;
            uint256 amountOut;

            isCallToken[i] = isCall;

            (result.baseCosts[i], result.feeCosts[i], amountOut) = _reassign(
                PoolStorage.layout(),
                msg.sender,
                maturity,
                strike64x64,
                isCall,
                args.contractSizes[i],
                args.newPrice64x64
            );

            if (isCall) {
                result.amountOutCall += amountOut;
            } else {
                result.amountOutPut += amountOut;
            }
        }

        if (result.amountOutCall > 0) {
            uint256 reassignmentCost;

            for (uint256 i; i < args.tokenIds.length; i++) {
                if (isCallToken[i] == false) continue;

                reassignmentCost += result.baseCosts[i];
                reassignmentCost += result.feeCosts[i];
            }

            _processAvailableFunds(
                msg.sender,
                result.amountOutCall,
                true,
                args.divest,
                true
            );

            _subUserTVL(
                PoolStorage.layout(),
                msg.sender,
                true,
                args.divest
                    ? reassignmentCost + result.amountOutCall
                    : reassignmentCost,
                args.utilizationCall64x64
            );
        }

        if (result.amountOutPut > 0) {
            uint256 reassignmentCost;

            for (uint256 i; i < args.tokenIds.length; i++) {
                if (isCallToken[i] == true) continue;

                reassignmentCost += result.baseCosts[i];
                reassignmentCost += result.feeCosts[i];
            }

            _processAvailableFunds(
                msg.sender,
                result.amountOutPut,
                false,
                args.divest,
                true
            );

            _subUserTVL(
                PoolStorage.layout(),
                msg.sender,
                false,
                args.divest
                    ? reassignmentCost + result.amountOutPut
                    : reassignmentCost,
                args.utilizationPut64x64
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
        int128 utilization64x64 = l.getUtilization64x64(isCall);

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
            divest ? tokenAmount : collateralFreed - tokenAmount,
            utilization64x64
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
        int128 utilization64x64 = l.getUtilization64x64(isCallPool);

        IPremiaMining(PREMIA_MINING_ADDRESS).claim(
            account,
            address(this),
            isCallPool,
            userTVL,
            userTVL,
            totalTVL,
            ABDKMath64x64Token.toDecimals(utilization64x64, 4)
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
            l.totalTVL[true],
            ABDKMath64x64Token.toDecimals(l.getUtilization64x64(true), 4)
        );

        IPremiaMining(PREMIA_MINING_ADDRESS).updatePool(
            address(this),
            false,
            l.totalTVL[false],
            ABDKMath64x64Token.toDecimals(l.getUtilization64x64(false), 4)
        );
    }
}
