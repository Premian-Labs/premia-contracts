// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";

import {IPremiaStaking} from "./IPremiaStaking.sol";
import {IPremiaStakingOld} from "./IPremiaStakingOld.sol";

contract PremiaStakingMigrator {
    // PREMIA token
    address private immutable PREMIA;
    // The old PremiaFeeDiscount contract
    address private immutable OLD_FEE_DISCOUNT;
    // The old PremiaStaking contract
    address private immutable OLD_STAKING;

    constructor(
        address premia,
        address oldFeeDiscount,
        address oldStaking
    ) {
        PREMIA = premia;
        OLD_FEE_DISCOUNT = oldFeeDiscount;
        OLD_STAKING = oldStaking;
    }

    /**
     * @notice Withdraw Premia from old fee discount / staking contract
     * @param user User for whom to migrate
     * @param amount Amount of old xPremia to migrate
     */
    function migrate(
        address user,
        uint256 amount,
        uint256,
        uint256
    ) external {
        require(msg.sender == OLD_FEE_DISCOUNT, "Not authorized");
        _withdraw(amount, user);
    }

    function _withdraw(uint256 amount, address to)
        internal
        returns (uint256 premiaWithdrawn)
    {
        IERC20(OLD_STAKING).transferFrom(msg.sender, address(this), amount);

        IPremiaStakingOld(OLD_STAKING).leave(amount);

        uint256 balance = IERC20(PREMIA).balanceOf(address(this));
        IERC20(PREMIA).transfer(to, balance);

        return balance;
    }
}
