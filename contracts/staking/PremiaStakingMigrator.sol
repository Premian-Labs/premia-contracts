// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
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
    // The new staking contract
    address private immutable NEW_STAKING;

    constructor(
        address premia,
        address oldFeeDiscount,
        address oldStaking,
        address newStaking
    ) {
        PREMIA = premia;
        OLD_FEE_DISCOUNT = oldFeeDiscount;
        OLD_STAKING = oldStaking;
        NEW_STAKING = newStaking;
    }

    /**
     * @notice Migrate old vePremia from old FeeDiscount contract to new vePremia
     * @param user User for whom to migrate
     * @param amount Amount of old vePremia to migrate
     */
    function migrate(
        address user,
        uint256 amount,
        uint256,
        uint256
    ) external {
        require(msg.sender == OLD_FEE_DISCOUNT, "Not authorized");
        _migrateWithoutLock(amount, user);
    }

    /**
     * @notice Migrate old vePremia to new vePremia using IERC2612 permit
     * @param amount Amount of old vePremia to migrate
     * @param deadline Deadline after which permit will fail
     * @param v V
     * @param r R
     * @param s S
     */
    function migrateWithoutLockWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 premiaDeposited, uint256 vePremiaMinted) {
        IERC2612(address(OLD_STAKING)).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        (premiaDeposited, vePremiaMinted) = _migrateWithoutLock(
            amount,
            msg.sender
        );
    }

    /**
     * @notice Migrate old vePremia to new vePremia
     * @param amount Amount of old vePremia to migrate
     * @return premiaDeposited Amount of premia deposited
     * @return vePremiaMinted Amount of vePremia minted
     */
    function migrateWithoutLock(uint256 amount)
        external
        returns (uint256 premiaDeposited, uint256 vePremiaMinted)
    {
        (premiaDeposited, vePremiaMinted) = _migrateWithoutLock(
            amount,
            msg.sender
        );
    }

    function _migrateWithoutLock(uint256 amount, address to)
        internal
        returns (uint256 premiaDeposited, uint256 vePremiaMinted)
    {
        IERC20(OLD_STAKING).transferFrom(msg.sender, address(this), amount);

        IPremiaStakingOld(OLD_STAKING).leave(amount);
        uint256 premiaBalance = IERC20(PREMIA).balanceOf(address(this));

        IERC20(PREMIA).approve(NEW_STAKING, amount);
        IPremiaStaking(NEW_STAKING).stake(amount, 0);

        uint256 vePremiaBalance = IERC20(NEW_STAKING).balanceOf(address(this));
        IERC20(NEW_STAKING).transfer(to, vePremiaBalance);

        return (premiaBalance, vePremiaBalance);
    }
}
