pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import "../interface/IFlashLoanReceiver.sol";
import "../interface/IPremiaOption.sol";

import "hardhat/console.sol";

contract TestFlashLoan is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    enum Mode{ PAY_BACK, PAY_BACK_NO_FEE, NO_PAY_BACK }

    Mode public mode = Mode.PAY_BACK;

    function setMode(Mode _mode) public {
        mode = _mode;
    }

    function execute(address _tokenAddress, uint256 _amount, uint256 _amountWithFee) override external {
        IERC20 token = IERC20(_tokenAddress);

        if (mode == Mode.PAY_BACK) {
            token.safeTransfer(msg.sender, _amountWithFee);
        } else if (mode == Mode.PAY_BACK_NO_FEE) {
            token.safeTransfer(msg.sender, _amount);
        }
    }
}
