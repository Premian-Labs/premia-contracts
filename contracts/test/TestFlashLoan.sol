// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IFlashLoanReceiver} from "../interface/IFlashLoanReceiver.sol";
import {IPremiaOption} from "../interface/IPremiaOption.sol";

contract TestFlashLoan is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    enum Mode {
        PAY_BACK,
        PAY_BACK_NO_FEE,
        NO_PAY_BACK
    }

    Mode public mode = Mode.PAY_BACK;

    function setMode(Mode _mode) public {
        mode = _mode;
    }

    function execute(
        address _tokenAddress,
        uint256 _amount,
        uint256 _amountWithFee
    ) external override {
        IERC20 token = IERC20(_tokenAddress);

        if (mode == Mode.PAY_BACK) {
            token.safeTransfer(msg.sender, _amountWithFee);
        } else if (mode == Mode.PAY_BACK_NO_FEE) {
            token.safeTransfer(msg.sender, _amount);
        }
    }
}
