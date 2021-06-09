// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from '@solidstate/contracts/access/Ownable.sol';
import {OwnableStorage} from '@solidstate/contracts/access/OwnableStorage.sol';

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @author Premia
/// @title 3 days timelock contract for dev fund
contract PremiaDevFund is Ownable {
    using SafeERC20 for IERC20;

    // The premia token
    IERC20 public premia;

    // The delay after which a withdrawal can be executed
    uint256 public immutable withdrawalDelay = 3 days;

    // The destination of current pending withdrawal
    address public pendingWithdrawalDestination;
    // The amount of current pending withdrawal
    uint256 public pendingWithdrawalAmount;
    // The timestamp after which the withdrawal can be executed
    uint256 public withdrawalETA;

    ////////////
    // Events //
    ////////////

    event WithdrawalStarted(address to, uint256 amount, uint256 eta);
    event WithdrawalCancelled(address to, uint256 amount, uint256 eta);
    event WithdrawalPerformed(address to, uint256 amount);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @param _premia The premia token
    constructor(IERC20 _premia) {
        OwnableStorage.layout().owner = msg.sender;
        premia = _premia;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @notice Initiate a withdrawal (Will have to go through 3 days timelock)
    /// @param _to Destination address of the withdrawal
    /// @param _amount The withdrawal amount
    function startWithdrawal(address _to, uint256 _amount) external onlyOwner {
        withdrawalETA = block.timestamp + withdrawalDelay;
        pendingWithdrawalDestination = _to;
        pendingWithdrawalAmount = _amount;

        emit WithdrawalStarted(_to, _amount, withdrawalETA);
    }

    /// @notice Execute a pending withdrawal, if it went through the 3 days timelock
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

    /// @notice Cancel a pending withdrawal
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
