// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {Ownable} from '@solidstate/contracts/access/Ownable.sol';
import {OwnableStorage} from '@solidstate/contracts/access/OwnableStorage.sol';

/// @author Premia
/// @title Vesting contract for Premia founder allocations, releasing the allocations over the course of a year
contract PremiaVesting is Ownable {
    using SafeERC20 for IERC20;

    // The premia token
    IERC20 public premia;

    // The timestamp at which release ends
    uint256 public endTimestamp;
    // The length of the release period (Once this period is passed, amount is fully unlocked)
    uint256 public releasePeriod = 365 days;
    // The timestamp at which last withdrawal has been done
    uint256 public lastWithdrawalTimestamp;

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    // @param _premia The premia token
    constructor(IERC20 _premia) {
        OwnableStorage.layout().owner = msg.sender;

        premia = _premia;
        endTimestamp = block.timestamp + releasePeriod;
        lastWithdrawalTimestamp = block.timestamp;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @notice Withdraw portion of allocation unlocked
    function withdraw() public onlyOwner {
        uint256 timestamp = block.timestamp;

        if (timestamp == lastWithdrawalTimestamp) return;

        uint256 _lastWithdrawalTimestamp = lastWithdrawalTimestamp;
        lastWithdrawalTimestamp = timestamp;

        uint256 balance = premia.balanceOf(address(this));

        if (timestamp >= endTimestamp) {
            premia.safeTransfer(msg.sender, balance);
        } else {

            uint256 elapsedSinceLastWithdrawal = timestamp - _lastWithdrawalTimestamp;
            uint256 timeLeft = endTimestamp - _lastWithdrawalTimestamp;
            premia.safeTransfer(msg.sender, balance * elapsedSinceLastWithdrawal / timeLeft);
        }
    }
}
