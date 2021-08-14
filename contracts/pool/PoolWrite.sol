// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {PoolStorage} from "./PoolStorage.sol";

import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {PoolBase} from "./PoolBase.sol";
import {IPoolWrite} from "./IPoolWrite.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolWrite is IPoolWrite, PoolBase {
    using SafeERC20 for IERC20;
    using ABDKMath64x64 for int128;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address weth,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 fee64x64
    ) PoolBase(weth, premiaMining, feeReceiver, feeDiscountAddress, fee64x64) {}

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
        override
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
     * @notice purchase option
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
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
    ) external payable override returns (uint256 baseCost, uint256 feeCost) {
        return _purchase(maturity, strike64x64, contractSize, isCall, maxCost);
    }

    /**
     * @notice swap eth to pay premium of the option and purchase option
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     * @param maxCost maximum acceptable cost after accounting for slippage
     * @return baseCost quantity of tokens required to purchase long position
     * @return feeCost quantity of tokens required to pay fees
     */
    function convertEthWith0xAndPurchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost,
        IPoolWrite.SwapArgs memory swapArgs
    ) external payable override returns (uint256 baseCost, uint256 feeCost) {
        uint256 sellTokenBalanceBefore = address(this).balance;
        uint256 buyTokenBalanceBefore = IERC20(swapArgs.buyToken).balanceOf(
            address(this)
        );

        require(msg.value > 0, "No ETH attached");
        (bool success, ) = swapArgs.swapTarget.call{value: msg.value}(
            swapArgs.swapCallData
        );
        require(success, "Swap call failed");

        (baseCost, feeCost) = _purchase(
            maturity,
            strike64x64,
            contractSize,
            isCall,
            maxCost
        );

        // Refund any ETH left from the swap
        uint256 sellTokenBalanceAfter = address(this).balance;
        require(
            sellTokenBalanceAfter >= sellTokenBalanceBefore,
            "Not enough eth left"
        );

        if (sellTokenBalanceAfter > sellTokenBalanceBefore) {
            payable(msg.sender).transfer(
                sellTokenBalanceAfter - sellTokenBalanceBefore
            );
        }

        uint256 buyTokenBalanceAfter = IERC20(swapArgs.buyToken).balanceOf(
            address(this)
        );
        require(
            buyTokenBalanceAfter >= buyTokenBalanceBefore,
            "Not enough buyToken left"
        );
        if (buyTokenBalanceAfter > buyTokenBalanceBefore) {
            IERC20(swapArgs.buyToken).safeTransfer(
                msg.sender,
                buyTokenBalanceAfter - buyTokenBalanceBefore
            );
        }
    }

    /**
     * @notice swap tokens to pay premium of the option and purchase option
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     * @param maxCost maximum acceptable cost after accounting for slippage
     * @return baseCost quantity of tokens required to purchase long position
     * @return feeCost quantity of tokens required to pay fees
     */
    function convertTokensWith0xAndPurchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost,
        IPoolWrite.SwapArgs memory swapArgs
    ) external payable override returns (uint256 baseCost, uint256 feeCost) {
        uint256 sellTokenBalanceBefore = IERC20(swapArgs.sellToken).balanceOf(
            address(this)
        );
        uint256 buyTokenBalanceBefore = IERC20(swapArgs.buyToken).balanceOf(
            address(this)
        );

        // ERC20
        require(msg.value == 0, "ETH attached");

        IERC20(swapArgs.sellToken).safeTransferFrom(
            msg.sender,
            address(this),
            swapArgs.maxSellAmount
        );

        IERC20(swapArgs.sellToken).approve(
            swapArgs.spender,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );

        (bool success, ) = swapArgs.swapTarget.call(swapArgs.swapCallData);
        require(success, "Swap call failed");

        IERC20(swapArgs.sellToken).approve(swapArgs.spender, 0);

        (baseCost, feeCost) = _purchase(
            maturity,
            strike64x64,
            contractSize,
            isCall,
            maxCost
        );

        // Refund any tokens left from the swap
        uint256 sellTokenBalanceAfter = IERC20(swapArgs.sellToken).balanceOf(
            address(this)
        );
        require(
            sellTokenBalanceAfter >= sellTokenBalanceBefore,
            "Not enough sellToken left"
        );

        if (sellTokenBalanceAfter > sellTokenBalanceBefore) {
            IERC20(swapArgs.sellToken).safeTransfer(
                msg.sender,
                sellTokenBalanceAfter - sellTokenBalanceBefore
            );
        }

        uint256 buyTokenBalanceAfter = IERC20(swapArgs.buyToken).balanceOf(
            address(this)
        );
        require(
            buyTokenBalanceAfter >= buyTokenBalanceBefore,
            "Not enough buyToken left"
        );
        if (buyTokenBalanceAfter > buyTokenBalanceBefore) {
            IERC20(swapArgs.buyToken).safeTransfer(
                msg.sender,
                buyTokenBalanceAfter - buyTokenBalanceBefore
            );
        }
    }

    /**
     * @notice write option without using liquidity from the pool on behalf of another address
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
    )
        external
        payable
        override
        returns (uint256 longTokenId, uint256 shortTokenId)
    {
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

        // mint long option token for designated receiver
        _mint(longReceiver, longTokenId, contractSize);
        // mint short option token for underwriter
        _mint(underwriter, shortTokenId, contractSize);

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
     * @notice Update pool data
     */
    function update()
        external
        override
        returns (int128 newEmaVarianceAnnualized64x64)
    {
        (, newEmaVarianceAnnualized64x64) = _update(PoolStorage.layout());
    }

    /**
     * @notice purchase option
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     * @param maxCost maximum acceptable cost after accounting for slippage
     * @return baseCost quantity of tokens required to purchase long position
     * @return feeCost quantity of tokens required to pay fees
     */
    function _purchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost
    ) internal returns (uint256 baseCost, uint256 feeCost) {
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
}
