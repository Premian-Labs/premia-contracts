// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";

import {IExchangeHelper} from "./interfaces/IExchangeHelper.sol";

/**
 * @title Premia Exchange Helper
 * @dev deployed standalone and referenced by ExchangeProxy
 * @dev do NOT set additional approval to this contract!
 */
contract ExchangeHelper is IExchangeHelper {
    using SafeERC20 for IERC20;

    /**
     * get token from caller, and perform any transaction
     * @param sourceToken source token to pull into this address
     * @param targetToken target token to buy
     * @param sourceTokenAmount amount of source token to trade
     * @param callee exchange address to call to execute the trade.
     * @param data calldata to execute the trade
     * @param refundAddress address that un-used source token goes to
     */
    function swapWithToken(
        address sourceToken,
        address targetToken,
        uint256 sourceTokenAmount,
        address callee,
        bytes calldata data,
        address refundAddress
    ) external returns (uint256 amountOut) {
        IERC20(sourceToken).approve(callee, sourceTokenAmount);

        (bool success, ) = callee.call(data);
        require(success, "swap failed");

        // refund unused sourceToken
        uint256 sourceLeft = IERC20(sourceToken).balanceOf(address(this));
        if (sourceLeft > 0)
            IERC20(sourceToken).safeTransfer(refundAddress, sourceLeft);

        // send the final amount back to the pool
        amountOut = IERC20(targetToken).balanceOf(address(this));
        IERC20(targetToken).safeTransfer(msg.sender, amountOut);
    }
}
