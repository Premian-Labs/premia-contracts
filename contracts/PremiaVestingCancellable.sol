// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';

/// @author Premia
/// @title Vesting contract for Premia founder allocations, releasing the allocations over the course of a year
contract PremiaVestingCancellable is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // The premia token
    IERC20 public premia;

    // The timestamp at which release ends
    uint256 public endTimestamp;
    // The length of the release period (Once this period is passed, amount is fully unlocked)
    uint256 public releasePeriod = 730 days; // 2 years
    // The timestamp at which last withdrawal has been done
    uint256 public lastWithdrawalTimestamp;
    // The Premia treasury address
    address public treasury;

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    // @param _premia The premia token
    constructor(IERC20 _premia, address _treasury) {
        premia = _premia;
        treasury = _treasury;
        endTimestamp = block.timestamp.add(releasePeriod);
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

            uint256 elapsedSinceLastWithdrawal = timestamp.sub(_lastWithdrawalTimestamp);
            uint256 timeLeft = endTimestamp.sub(_lastWithdrawalTimestamp);
            premia.safeTransfer(_user, balance.mul(elapsedSinceLastWithdrawal).div(timeLeft));
        }
    }

    function cancel() public {
        require(msg.sender == treasury, "Not treasury");
        // Send pending withdrawal to contract owner
        _withdraw(owner());

        // Send balance left to Premia treasury
        uint256 balance = premia.balanceOf(address(this));
        premia.safeTransfer(treasury, balance);
    }
}
