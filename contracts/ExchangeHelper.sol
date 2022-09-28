// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IExchangeHelper} from "./interfaces/IExchangeHelper.sol";

/**
 * @title Premia Exchange Helper
 * @dev deployed standalone and referenced by ExchangeProxy
 * @dev do NOT set additional approval to this contract!
 */
contract ExchangeHelper is IExchangeHelper {
    using SafeERC20 for IERC20;

    /**
     * @inheritdoc IExchangeHelper
     */
    function swapWithToken(
        address sourceToken,
        address targetToken,
        uint256 sourceTokenAmount,
        address callee,
        address allowanceTarget,
        bytes calldata data,
        address refundAddress
    ) external returns (uint256 amountOut) {
        IERC20(sourceToken).approve(allowanceTarget, sourceTokenAmount);

        (bool success, ) = callee.call(data);
        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

        // refund unused sourceToken
        uint256 sourceLeft = IERC20(sourceToken).balanceOf(address(this));
        if (sourceLeft > 0)
            IERC20(sourceToken).safeTransfer(refundAddress, sourceLeft);

        // send the final amount back to the pool
        amountOut = IERC20(targetToken).balanceOf(address(this));
        IERC20(targetToken).safeTransfer(msg.sender, amountOut);
    }
}
