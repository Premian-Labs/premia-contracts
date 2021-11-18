// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {OwnableInternal} from "@solidstate/contracts/access/OwnableInternal.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {PremiaStaking} from "./PremiaStaking.sol";
import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";
import {IFeeDiscount} from "./IFeeDiscount.sol";

/**
 * @author Premia
 * @title A contract allowing you to lock xPremia to get Premia protocol fee discounts
 */
contract FeeDiscount is IFeeDiscount, PremiaStaking, OwnableInternal {
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

    ///////////
    // Admin //
    ///////////

    /**
     * @notice Set a stake period multiplier
     * @param _secondsLocked The length (in seconds) that the stake will be locked for
     * @param _multiplier The multiplier (In basis points) that users will get from choosing this staking period
     */
    function setStakePeriod(uint256 _secondsLocked, uint256 _multiplier)
        external
        onlyOwner
    {
        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();

        if (_isInArray(_secondsLocked, l.existingStakePeriods)) {
            l.existingStakePeriods.push(_secondsLocked);
        }

        l.stakePeriods[_secondsLocked] = _multiplier;
    }

    /**
     * @notice Set new amounts and discounts values for stake levels
     * @dev Previous stake levels will be removed and replace by the new ones given
     * @param _stakeLevels The new stake levels to set
     */
    function setStakeLevels(FeeDiscountStorage.StakeLevel[] memory _stakeLevels)
        external
        onlyOwner
    {
        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();

        for (uint256 i = 0; i < _stakeLevels.length; i++) {
            if (i > 0) {
                require(
                    _stakeLevels[i].amount > _stakeLevels[i - 1].amount &&
                        _stakeLevels[i].discount > _stakeLevels[i - 1].discount,
                    "Wrong stake level"
                );
            }
        }

        delete l.stakeLevels;

        for (uint256 i = 0; i < _stakeLevels.length; i++) {
            l.stakeLevels.push(_stakeLevels[i]);
        }
    }

    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    /**
     * @inheritdoc IFeeDiscount
     */
    function stake(uint256 _amount, uint256 _period) external override {
        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();

        require(l.stakePeriods[_period] > 0, "Stake period does not exists");
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
        require(
            l.stakePeriods[user.stakePeriod] == 0 ||
                user.lockedUntil <= block.timestamp,
            "Stake still locked"
        );

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
    function stakeLevelsLength() external view override returns (uint256) {
        return FeeDiscountStorage.layout().stakeLevels.length;
    }

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
            (user.balance * l.stakePeriods[user.stakePeriod]) /
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
        FeeDiscountStorage.Layout storage l = FeeDiscountStorage.layout();
        uint256 userBalance = getStakeAmountWithBonus(_user);

        for (uint256 i = 0; i < l.stakeLevels.length; i++) {
            FeeDiscountStorage.StakeLevel memory level = l.stakeLevels[i];

            if (userBalance < level.amount) {
                uint256 amountPrevLevel;
                uint256 discountPrevLevel;

                // If stake is lower, user is in this level, and we need to LERP with prev level to get discount value
                if (i > 0) {
                    amountPrevLevel = l.stakeLevels[i - 1].amount;
                    discountPrevLevel = l.stakeLevels[i - 1].discount;
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
        return l.stakeLevels[l.stakeLevels.length - 1].discount;
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
}
