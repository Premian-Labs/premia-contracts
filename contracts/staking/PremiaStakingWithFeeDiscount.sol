// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";

import {PremiaStaking} from "./PremiaStaking.sol";
import {FeeDiscount} from "./FeeDiscount.sol";
import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";

import {IPremiaStakingOld} from "./IPremiaStakingOld.sol";
import {IPremiaStakingWithFeeDiscount} from "./IPremiaStakingWithFeeDiscount.sol";

contract PremiaStakingWithFeeDiscount is
    IPremiaStakingWithFeeDiscount,
    PremiaStaking,
    FeeDiscount
{
    using SafeCast for uint256;

    // The old PremiaFeeDiscount contract
    address private immutable OLD_FEE_DISCOUNT;
    // The old PremiaStaking contract
    address private immutable OLD_STAKING;

    constructor(
        address lzEndpoint,
        address premia,
        address oldFeeDiscount,
        address oldStaking
    ) PremiaStaking(lzEndpoint, premia) FeeDiscount(address(this)) {
        OLD_FEE_DISCOUNT = oldFeeDiscount;
        OLD_STAKING = oldStaking;
    }

    function _transferXPremia(
        address holder,
        address recipient,
        uint256 amount
    ) internal override {
        _transfer(holder, recipient, amount);
    }

    /**
     * @notice Migrate old xPremia from old FeeDiscount contract to new xPremia
     * @param user User for whom to migrate
     * @param amount Amount of old xPremia to migrate
     * @param stakePeriod Stake period selected in old contract
     * @param lockedUntil Lock end date from old contract
     */
    function migrate(
        address user,
        uint256 amount,
        uint256 stakePeriod,
        uint256 lockedUntil
    ) external {
        require(msg.sender == OLD_FEE_DISCOUNT, "Not authorized");

        (uint256 premiaDeposited, uint256 xPremiaMinted) = _migrateWithoutLock(
            amount,
            address(this)
        );

        emit Deposit(user, premiaDeposited);

        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();
        FeeDiscountStorage.UserInfo storage userInfo = l.userInfo[user];

        uint64 _lockedUntil = lockedUntil.toUint64();
        uint64 _stakePeriod = stakePeriod.toUint64();

        userInfo.balance += xPremiaMinted;

        if (_lockedUntil > userInfo.lockedUntil) {
            userInfo.lockedUntil = lockedUntil.toUint64();
        }

        if (_stakePeriod > userInfo.stakePeriod) {
            userInfo.stakePeriod = stakePeriod.toUint64();
        }
    }

    /**
     * @notice Migrate old xPremia to new xPremia using IERC2612 permit
     * @param amount Amount of old xPremia to migrate
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
    ) external returns (uint256 premiaDeposited, uint256 xPremiaMinted) {
        IERC2612(address(OLD_STAKING)).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        (premiaDeposited, xPremiaMinted) = _migrateWithoutLock(
            amount,
            msg.sender
        );
        emit Deposit(msg.sender, premiaDeposited);
    }

    /**
     * @notice Migrate old xPremia to new xPremia
     * @param amount Amount of old xPremia to migrate
     * @return premiaDeposited Amount of premia deposited
     * @return xPremiaMinted Amount of xPremia minted
     */
    function migrateWithoutLock(uint256 amount)
        external
        returns (uint256 premiaDeposited, uint256 xPremiaMinted)
    {
        (premiaDeposited, xPremiaMinted) = _migrateWithoutLock(
            amount,
            msg.sender
        );
        emit Deposit(msg.sender, premiaDeposited);
    }

    function _migrateWithoutLock(uint256 amount, address to)
        internal
        returns (uint256 premiaDeposited, uint256 xPremiaMinted)
    {
        _updateRewards();

        // Gets the amount of Premia locked in the contract
        uint256 totalPremia = _getStakedPremiaAmount();

        //

        IERC20(OLD_STAKING).transferFrom(msg.sender, address(this), amount);

        uint256 oldPremiaBalance = IERC20(PREMIA).balanceOf(address(this));
        IPremiaStakingOld(OLD_STAKING).leave(amount);
        uint256 newPremiaBalance = IERC20(PREMIA).balanceOf(address(this));

        uint256 toDeposit = newPremiaBalance - oldPremiaBalance;

        return (toDeposit, _mintShares(to, toDeposit, totalPremia));
    }
}
