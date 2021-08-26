// SPDX-License-Identifier: UNLICENSED

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

    // TODO: implement more flexible solution in SolidState
    // cannot bypass the following:
    // balanceOf
    // setApprovalForAll
    // isApprovedForAll
    // safeTransferFrom
    // totalSupply

    function balanceOfBatch(address[] calldata, uint256[] calldata)
        public
        pure
        override
        returns (uint256[] memory)
    {
        revert("unimplemented");
    }

    function safeBatchTransferFrom(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) public pure override {
        revert("unimplemented");
    }

    function totalHolders(uint256) public pure override returns (uint256) {
        revert("unimplemented");
    }

    function accountsByToken(uint256)
        public
        pure
        override
        returns (address[] memory)
    {
        revert("unimplemented");
    }

    function tokensByAccount(address)
        public
        pure
        override
        returns (uint256[] memory)
    {
        revert("unimplemented");
    }

    /**
     * @notice set timestamp after which reinvestment is disabled
     * @param timestamp timestamp to begin divestment
     * @param isCallPool whether we set divestment timestamp for the call pool or put pool
     */
    function setDivestmentTimestamp(uint64 timestamp, bool isCallPool)
        external
        override
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        require(
            timestamp >= l.depositedAt[msg.sender][isCallPool] + (1 days),
            "liq lock 1d"
        );
        l.divestmentTimestamps[msg.sender][isCallPool] = timestamp;
    }

    /**
     * @notice deposit underlying currency, underwriting calls of that currency with respect to base currency
     * @param amount quantity of underlying currency to deposit
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     */
    function deposit(uint256 amount, bool isCallPool) public payable override {
        PoolStorage.Layout storage l = PoolStorage.layout();

        // Reset gradual divestment timestamp
        delete l.divestmentTimestamps[msg.sender][isCallPool];

        uint256 cap = _getPoolCapAmount(l, isCallPool);

        require(
            l.totalTVL[isCallPool] + amount <= cap,
            "pool deposit cap reached"
        );

        require(
            l.userTVL[msg.sender][isCallPool] + amount <= cap / 10,
            "individual deposit cap reached"
        );

        _processPendingDeposits(l, isCallPool);

        l.depositedAt[msg.sender][isCallPool] = block.timestamp;
        _addUserTVL(l, msg.sender, isCallPool, amount);
        _pullFrom(msg.sender, _getPoolToken(isCallPool), amount);

        _addToDepositQueue(msg.sender, amount, isCallPool);

        emit Deposit(msg.sender, isCallPool, amount);
    }

    /**
     * @notice deposit underlying currency, underwriting calls of that currency with respect to base currency
     * @param amount quantity of underlying currency to deposit
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool

     * @param amountOut amount out of tokens requested. If 0, we will swap exact amount necessary to pay the quote
     * @param amountInMax amount in max of tokens
     * @param path swap path
     * @param isSushi whether we use sushi or uniV2 for the swap
     */
    function swapAndDeposit(
        uint256 amount,
        bool isCallPool,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        bool isSushi
    ) external payable override {
        // If no amountOut has been passed, we swap the exact deposit amount specified
        if (amountOut == 0) {
            amountOut = amount;
        }

        _swapTokensForExactTokens(amountOut, amountInMax, path, isSushi);

        deposit(amount, isCallPool);
    }

    /**
     * @notice redeem pool share tokens for underlying asset
     * @param amount quantity of share tokens to redeem
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
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

        _subUserTVL(l, msg.sender, isCallPool, amount);
        _pushTo(msg.sender, _getPoolToken(isCallPool), amount);
        emit Withdrawal(msg.sender, isCallPool, depositedAt, amount);
    }

    /**
     * @notice reassign short position to new underwriter
     * @param tokenId ERC1155 token id (long or short)
     * @param contractSize quantity of option contract tokens to reassign
     * @return baseCost quantity of tokens required to reassign short position
     * @return feeCost quantity of tokens required to pay fees
     * @return amountOut quantity of liquidity freed and transferred to owner
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
     * @notice reassign set of short position to new underwriter
     * @param tokenIds array of ERC1155 token ids (long or short)
     * @param contractSizes array of quantities of option contract tokens to reassign
     * @return baseCosts quantities of tokens required to reassign each short position
     * @return feeCosts quantities of tokens required to pay fees
     * @return amountOutCall quantity of call pool liquidity freed and transferred to owner
     * @return amountOutPut quantity of put pool liquidity freed and transferred to owner
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
        require(tokenIds.length == contractSizes.length, "TODO");

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
     * @notice withdraw all free liquidity and reassign set of short position to new underwriter
     * @param isCallPool true for call, false for put
     * @param tokenIds array of ERC1155 token ids (long or short)
     * @param contractSizes array of quantities of option contract tokens to reassign
     * @return baseCosts quantities of tokens required to reassign each short position
     * @return feeCosts quantities of tokens required to pay fees
     * @return amountOutCall quantity of call pool liquidity freed and transferred to owner
     * @return amountOutPut quantity of put pool liquidity freed and transferred to owner
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
        uint256 balance = balanceOf(
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
     * @notice transfer accumulated fees to the fee receiver
     * @return amountOutCall quantity of underlying tokens transferred
     * @return amountOutPut quantity of base tokens transferred
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
     * @notice burn corresponding long and short option tokens and withdraw collateral
     * @param tokenId ERC1155 token id (long or short)
     * @param contractSize quantity of option contract tokens to annihilate
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

    function claimRewards(bool isCallPool) external override {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 userTVL = l.userTVL[msg.sender][isCallPool];
        uint256 totalTVL = l.totalTVL[isCallPool];

        IPremiaMining(PREMIA_MINING_ADDRESS).claim(
            msg.sender,
            address(this),
            isCallPool,
            userTVL,
            userTVL,
            totalTVL
        );
    }

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
}
