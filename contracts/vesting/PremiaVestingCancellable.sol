// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {Ownable} from "@solidstate/contracts/access/ownable/Ownable.sol";
import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";

/// @author Premia
/// @title Vesting contract releasing premia over the course of 2 years, and cancellable by a third party
contract PremiaVestingCancellable is Ownable {
    using SafeERC20 for IERC20;

    // The premia token
    IERC20 public premia;

    // The timestamp at which release ends
    uint256 public endTimestamp;
    // The length of the release period (Once this period is passed, amount is fully unlocked)
    uint256 public constant releasePeriod = 730 days; // 2 years
    // The minimum release period before contract can be cancelled
    uint256 public constant minReleasePeriod = 180 days; // 6 months
    // The timestamp at which last withdrawal has been done
    uint256 public lastWithdrawalTimestamp;
    // The premia treasury address
    address public treasury;
    // The thirdParty address
    address public thirdParty;

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    // @param _premia The premia token
    constructor(IERC20 _premia, address _treasury, address _thirdParty) {
        OwnableStorage.layout().owner = msg.sender;

        premia = _premia;
        treasury = _treasury;
        thirdParty = _thirdParty;
        endTimestamp = block.timestamp + releasePeriod;
        lastWithdrawalTimestamp = block.timestamp;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @notice Withdraw portion of allocation unlocked
    function withdraw() public onlyOwner {
        _withdraw(msg.sender);
    }

    /// @notice Withdraw portion of allocation unlocked
    function _withdraw(address _user) internal {
        uint256 timestamp = block.timestamp;

        if (timestamp == lastWithdrawalTimestamp) return;

        uint256 _lastWithdrawalTimestamp = lastWithdrawalTimestamp;
        lastWithdrawalTimestamp = timestamp;

        uint256 balance = premia.balanceOf(address(this));

        if (timestamp >= endTimestamp) {
            premia.safeTransfer(_user, balance);
        } else {
            uint256 elapsedSinceLastWithdrawal = timestamp -
                _lastWithdrawalTimestamp;
            uint256 timeLeft = endTimestamp - _lastWithdrawalTimestamp;
            premia.safeTransfer(
                _user,
                (balance * elapsedSinceLastWithdrawal) / timeLeft
            );
        }
    }

    function cancel() external {
        require(msg.sender == thirdParty, "Not thirdParty");
        require(
            block.timestamp >= endTimestamp - releasePeriod + minReleasePeriod,
            "Min release period not ended"
        );
        // Send pending withdrawal to contract owner
        _withdraw(owner());

        // Send balance left to Premia treasury
        uint256 balance = premia.balanceOf(address(this));
        premia.safeTransfer(treasury, balance);
    }
}
