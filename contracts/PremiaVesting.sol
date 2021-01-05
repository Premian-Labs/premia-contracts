// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';

contract PremiaVesting is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public premia;

    // The timestamp at which release ends
    uint256 public endTimestamp;
    // The length of the release period (Once this period is passed, amount is fully unlocked)
    uint256 public releasePeriod = 365 days;
    // The timestamp at which last withdrawal has been done
    uint256 public lastWithdrawalTimestamp;

    constructor(IERC20 _premia) public {
        premia = _premia;
        endTimestamp = block.timestamp.add(releasePeriod);
        lastWithdrawalTimestamp = block.timestamp;
    }

    function withdraw() public onlyOwner {
        uint256 timestamp = block.timestamp;

        if (timestamp == lastWithdrawalTimestamp) return;

        uint256 _lastWithdrawalTimestamp = lastWithdrawalTimestamp;
        lastWithdrawalTimestamp = timestamp;

        uint256 balance = premia.balanceOf(address(this));

        if (timestamp >= endTimestamp) {
            premia.safeTransfer(msg.sender, balance);
        } else {

            uint256 elapsedSinceLastWithdrawal = timestamp.sub(_lastWithdrawalTimestamp);
            uint256 timeLeft = endTimestamp.sub(_lastWithdrawalTimestamp);
            premia.safeTransfer(msg.sender, balance.mul(elapsedSinceLastWithdrawal).div(timeLeft));
        }
    }
}
