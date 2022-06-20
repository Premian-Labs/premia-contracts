// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PoolStorage} from "./PoolStorage.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "@solidstate/contracts/utils/IWETH.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {IExchangeHelper} from "../interfaces/IExchangeHelper.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
abstract contract PoolSwap is PoolInternal {
    using SafeERC20 for IERC20;

    address internal immutable EXCHANGE_HELPER;

    constructor(
        address ivolOracle,
        address nativeToken,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 feePremium64x64,
        int128 feeApy64x64,
        address exchangeHelper
    )
        PoolInternal(
            ivolOracle,
            nativeToken,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            feePremium64x64,
            feeApy64x64
        )
    {
        EXCHANGE_HELPER = exchangeHelper;
    }

    /**
     * @dev pull token from user, send to exchangeHelper and trigger a trade from exchangeHelper
     * @param tokenIn token to be taken from user
     * @param tokenOut token to swap for. should always equal to the pool token.
     * @param amountInMax maximum amount to used for swap. The reset will be refunded
     * @param amountOutMin minimum amount taken from the trade.
     * @param refundAddress where to send the un-used tokenIn, in any
     * @param callee exchange address to execute the trade
     * @param data calldata to execute the trade
     * @return amountCredited amount of tokenOut we got from the trade.
     */
    function _swapForPoolTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 amountOutMin,
        address callee,
        bytes memory data,
        address refundAddress
    ) internal returns (uint256 amountCredited) {
        if (msg.value > 0) {
            require(tokenIn == NATIVE_TOKEN, "wrong tokenIn");
            IWETH(NATIVE_TOKEN).deposit{value: msg.value}();
            IWETH(NATIVE_TOKEN).transfer(EXCHANGE_HELPER, msg.value);
        }
        if (amountInMax > 0) {
            IERC20(tokenIn).safeTransferFrom(
                msg.sender,
                EXCHANGE_HELPER,
                amountInMax
            );
        }

        amountCredited = IExchangeHelper(EXCHANGE_HELPER).swapWithToken(
            tokenIn,
            tokenOut,
            amountInMax + msg.value,
            callee,
            data,
            refundAddress
        );
        require(amountCredited >= amountOutMin, "not enough output from trade");
    }
}
