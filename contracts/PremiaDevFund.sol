// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';

contract PremiaDevFund is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public premia;

    uint256 public immutable withdrawalDelay = 3 days;

    address public pendingWithdrawalDestination;
    uint256 public pendingWithdrawalAmount;
    uint256 public withdrawalETA;

    event WithdrawalStarted(address to, uint256 amount, uint256 eta);
    event WithdrawalCancelled(address to, uint256 amount, uint256 eta);
    event WithdrawalPerformed(address to, uint256 amount);

    constructor(IERC20 _premia) {
        premia = _premia;
    }

    function startWithdrawal(address _to, uint256 _amount) external onlyOwner {
        withdrawalETA = block.timestamp.add(withdrawalDelay);
        pendingWithdrawalDestination = _to;
        pendingWithdrawalAmount = _amount;

        emit WithdrawalStarted(_to, _amount, withdrawalETA);
    }

    function doWithdraw() external onlyOwner {
        require(withdrawalETA > 0, "No pending withdrawal");
        require(block.timestamp >= withdrawalETA, "Still timelocked");
        require(pendingWithdrawalDestination != address(0), "No destination set");

        uint256 amount = pendingWithdrawalAmount;
        address to = pendingWithdrawalDestination;

        delete pendingWithdrawalAmount;
        delete pendingWithdrawalDestination;
        delete withdrawalETA;

        premia.safeTransfer(to, amount);

        emit WithdrawalPerformed(to, amount);
    }

    function cancelWithdrawal() external onlyOwner {
        uint256 amount = pendingWithdrawalAmount;
        address to = pendingWithdrawalDestination;
        uint256 eta = withdrawalETA;

        delete pendingWithdrawalAmount;
        delete pendingWithdrawalDestination;
        delete withdrawalETA;

        emit WithdrawalCancelled(to, amount, eta);
    }
}
