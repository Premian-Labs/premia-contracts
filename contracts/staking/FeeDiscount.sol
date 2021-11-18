// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {PremiaStaking} from "./PremiaStaking.sol";
import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";
import {IFeeDiscount} from "./IFeeDiscount.sol";

/**
 * @author Premia
 * @title A contract allowing you to lock xPremia to get Premia protocol fee discounts
 */
contract FeeDiscount is IFeeDiscount, PremiaStaking {
    using SafeCast for uint256;

    uint256 internal constant INVERSE_BASIS_POINT = 1e4;

    ////////////
    // Events //
    ////////////

    event Staked(
        address indexed user,
        uint256 amount,
        uint256 stakePeriod,
        uint256 lockedUntil
    );
    event Unstaked(address indexed user, uint256 amount);

    //////////////////////////////////////////////////

    constructor(address premia) PremiaStaking(premia) {}

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    /**
     * @inheritdoc IFeeDiscount
     */
    function stake(uint256 _amount, uint256 _period) external override {
        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();

        require(
            _getStakePeriodMultiplier(_period) > 0,
            "Stake period does not exists"
        );
        FeeDiscountStorage.UserInfo storage user = l.userInfo[msg.sender];

        uint256 lockedUntil = block.timestamp + _period;
        require(
            lockedUntil > user.lockedUntil,
            "Cannot add stake with lower stake period"
        );

        _transfer(msg.sender, address(this), _amount);
        user.balance = user.balance + _amount;
        user.lockedUntil = lockedUntil.toUint64();
        user.stakePeriod = _period.toUint64();

        emit Staked(msg.sender, _amount, _period, lockedUntil);
    }

    /**
     * @inheritdoc IFeeDiscount
     */
    function unstake(uint256 _amount) external override {
        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();

        FeeDiscountStorage.UserInfo storage user = l.userInfo[msg.sender];

        // We allow unstake if the stakePeriod that the user used has been disabled
        require(user.lockedUntil <= block.timestamp, "Stake still locked");

        user.balance -= _amount;
        _transfer(address(this), msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    /**
     * @inheritdoc IFeeDiscount
     */
    function getStakeAmountWithBonus(address _user)
        public
        view
        override
        returns (uint256)
    {
        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();

        FeeDiscountStorage.UserInfo memory user = l.userInfo[_user];
        return
            (user.balance * _getStakePeriodMultiplier(user.stakePeriod)) /
            INVERSE_BASIS_POINT;
    }

    /**
     * @inheritdoc IFeeDiscount
     */
    function getDiscount(address _user)
        external
        view
        override
        returns (uint256)
    {
        uint256 userBalance = getStakeAmountWithBonus(_user);

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
        override
        returns (IFeeDiscount.StakeLevel[] memory stakeLevels)
    {
        return _getStakeLevels();
    }

    /**
     * @inheritdoc IFeeDiscount
     */
    function getStakePeriodMultiplier(uint256 _period)
        external
        pure
        override
        returns (uint256)
    {
        return _getStakePeriodMultiplier(_period);
    }

    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    /**
     * @notice Utility function to check if a value is inside an array
     * @param _value The value to look for
     * @param _array The array to check
     * @return Whether the value is in the array or not
     */
    function _isInArray(uint256 _value, uint256[] memory _array)
        internal
        pure
        returns (bool)
    {
        uint256 length = _array.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_array[i] == _value) {
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

    function _getStakePeriodMultiplier(uint256 _period)
        internal
        pure
        returns (uint256)
    {
        if (_period == 30 days) return 10000; // x1
        if (_period == 90 days) return 12500; // x1.25
        if (_period == 180 days) return 15000; // x1.5
        if (_period == 360 days) return 20000; // x2

        return 0;
    }
}
