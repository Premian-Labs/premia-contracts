// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IERC20, SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";

import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";
import {IFeeDiscount} from "./IFeeDiscount.sol";

/**
 * @author Premia
 * @title A contract allowing you to lock xPremia to get Premia protocol fee discounts
 */
contract FeeDiscount is IFeeDiscount {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    address internal immutable xPREMIA;
    uint256 internal constant INVERSE_BASIS_POINT = 1e4;

    constructor(address xPremia) {
        xPREMIA = xPremia;
    }

    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    /**
     * @inheritdoc IFeeDiscount
     */
    function stakeWithPermit(
        uint256 amount,
        uint256 period,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IERC2612(address(xPREMIA)).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        _stake(amount, period);
    }

    /**
     * @inheritdoc IFeeDiscount
     */
    function stake(uint256 amount, uint256 period) external {
        _stake(amount, period);
    }

    function _beforeStake(uint256 amount, uint256 period) internal virtual {}

    function _stake(uint256 amount, uint256 period) internal {
        _beforeStake(amount, period);

        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();

        require(
            _getStakePeriodMultiplier(period) > 0,
            "Stake period does not exists"
        );
        FeeDiscountStorage.UserInfo storage user = l.userInfo[msg.sender];

        uint256 lockedUntil = block.timestamp + period;
        require(
            lockedUntil > user.lockedUntil,
            "Cannot add stake with lower stake period"
        );

        _transferXPremia(msg.sender, address(this), amount);
        user.balance = user.balance + amount;
        user.lockedUntil = lockedUntil.toUint64();
        user.stakePeriod = period.toUint64();

        emit Staked(msg.sender, amount, period, lockedUntil);
    }

    function _beforeUnstake(uint256 amount) internal virtual {}

    /**
     * @inheritdoc IFeeDiscount
     */
    function unstake(uint256 amount) external {
        _beforeUnstake(amount);

        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();
        FeeDiscountStorage.UserInfo storage user = l.userInfo[msg.sender];

        // We allow unstake if the stakePeriod that the user used has been disabled
        require(user.lockedUntil <= block.timestamp, "Stake still locked");

        user.balance -= amount;
        _transferXPremia(address(this), msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    /**
     * @inheritdoc IFeeDiscount
     */
    function getStakeAmountWithBonus(address user)
        external
        view
        returns (uint256)
    {
        return _getStakeAmountWithBonus(user);
    }

    /**
     * @inheritdoc IFeeDiscount
     */
    function getDiscount(address user) external view returns (uint256) {
        uint256 userBalance = _getStakeAmountWithBonus(user);

        IFeeDiscount.StakeLevel[] memory stakeLevels = _getStakeLevels();

        for (uint256 i = 0; i < stakeLevels.length; i++) {
            IFeeDiscount.StakeLevel memory level = stakeLevels[i];

            if (userBalance < level.amount) {
                uint256 amountPrevLevel;
                uint256 discountPrevLevel;

                // If stake is lower, user is in this level, and we need to LERP with prev level to get discount value
                if (i > 0) {
                    amountPrevLevel = stakeLevels[i - 1].amount;
                    discountPrevLevel = stakeLevels[i - 1].discount;
                } else {
                    // If this is the first level, prev level is 0 / 0
                    amountPrevLevel = 0;
                    discountPrevLevel = 0;
                }

                uint256 remappedDiscount = level.discount - discountPrevLevel;

                uint256 remappedAmount = level.amount - amountPrevLevel;
                uint256 remappedBalance = userBalance - amountPrevLevel;
                uint256 levelProgress = (remappedBalance *
                    INVERSE_BASIS_POINT) / remappedAmount;

                return
                    discountPrevLevel +
                    ((remappedDiscount * levelProgress) / INVERSE_BASIS_POINT);
            }
        }

        // If no match found it means user is >= max possible stake, and therefore has max discount possible
        return stakeLevels[stakeLevels.length - 1].discount;
    }

    /**
     * @inheritdoc IFeeDiscount
     */
    function getStakeLevels()
        external
        pure
        returns (IFeeDiscount.StakeLevel[] memory stakeLevels)
    {
        return _getStakeLevels();
    }

    /**
     * @inheritdoc IFeeDiscount
     */
    function getStakePeriodMultiplier(uint256 period)
        external
        pure
        returns (uint256)
    {
        return _getStakePeriodMultiplier(period);
    }

    /**
     * @inheritdoc IFeeDiscount
     */
    function getUserInfo(address user)
        external
        view
        returns (FeeDiscountStorage.UserInfo memory)
    {
        return FeeDiscountStorage.layout().userInfo[user];
    }

    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    /**
     * @notice Utility function to check if a value is inside an array
     * @param value The value to look for
     * @param array The array to check
     * @return Whether the value is in the array or not
     */
    function _isInArray(uint256 value, uint256[] memory array)
        internal
        pure
        returns (bool)
    {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; ++i) {
            if (array[i] == value) {
                return true;
            }
        }

        return false;
    }

    function _getStakeLevels()
        internal
        pure
        returns (IFeeDiscount.StakeLevel[] memory stakeLevels)
    {
        stakeLevels = new IFeeDiscount.StakeLevel[](4);

        stakeLevels[0] = IFeeDiscount.StakeLevel(5000 * 1e18, 2500); // -25%
        stakeLevels[1] = IFeeDiscount.StakeLevel(50000 * 1e18, 5000); // -50%
        stakeLevels[2] = IFeeDiscount.StakeLevel(250000 * 1e18, 7500); // -75%
        stakeLevels[3] = IFeeDiscount.StakeLevel(500000 * 1e18, 9500); // -95%
    }

    function _getStakePeriodMultiplier(uint256 period)
        internal
        pure
        returns (uint256)
    {
        uint256 oneYear = 365 days;

        if (period == 0) return 2500; // x0.25
        if (period >= 4 * oneYear) return 42500; // x4.25

        return 2500 + (period * 1e4) / oneYear; // 0.25x + 1.0x per year lockup
    }

    function _getStakeAmountWithBonus(address user)
        internal
        view
        returns (uint256)
    {
        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();

        FeeDiscountStorage.UserInfo memory userInfo = l.userInfo[user];
        return
            (userInfo.balance *
                _getStakePeriodMultiplier(userInfo.stakePeriod)) /
            INVERSE_BASIS_POINT;
    }

    /**
     * @notice transfer tokens from holder to recipient
     * @param holder owner of tokens to be transferred
     * @param recipient beneficiary of transfer
     * @param amount quantity of tokens transferred
     */
    function _transferXPremia(
        address holder,
        address recipient,
        uint256 amount
    ) internal virtual {
        if (holder == address(this)) {
            IERC20(xPREMIA).safeTransfer(recipient, amount);
        } else {
            IERC20(xPREMIA).safeTransferFrom(holder, recipient, amount);
        }
    }
}
