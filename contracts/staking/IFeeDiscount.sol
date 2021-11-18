// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";

interface IFeeDiscount {
    struct StakeLevel {
        uint256 amount; // Amount to stake
        uint256 discount; // Discount when amount is reached
    }

    /**
     * @notice Stake using IERC2612 permit
     * @param _amount The amount of xPremia to stake
     * @param _period The lockup period (in seconds)
     * @param _deadline Deadline after which permit will fail
     * @param _v V
     * @param _r R
     * @param _s S
     */
    function stakeWithPermit(
        uint256 _amount,
        uint256 _period,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    /**
     * @notice Lockup xPremia for protocol fee discounts
     *          Longer period of locking will apply a multiplier on the amount staked, in the fee discount calculation
     * @param _amount The amount of xPremia to stake
     * @param _period The lockup period (in seconds)
     */
    function stake(uint256 _amount, uint256 _period) external;

    /**
     * @notice Unstake xPremia (If lockup period has ended)
     * @param _amount The amount of xPremia to unstake
     */
    function unstake(uint256 _amount) external;

    //////////
    // View //
    //////////

    /**
     * Calculate the stake amount of a user, after applying the bonus from the lockup period chosen
     * @param _user The user from which to query the stake amount
     * @return The user stake amount after applying the bonus
     */
    function getStakeAmountWithBonus(address _user)
        external
        view
        returns (uint256);

    /**
     * @notice Calculate the % of fee discount for user, based on his stake
     * @param _user The _user for which the discount is for
     * @return Percentage of protocol fee discount (in basis point)
     *         Ex : 1000 = 10% fee discount
     */
    function getDiscount(address _user) external view returns (uint256);

    /**
     * @notice Get stake levels
     * @return Stake levels
     *         Ex : 2500 = -25%
     */
    function getStakeLevels() external returns (StakeLevel[] memory);

    /**
     * @notice Get stake period multiplier
     * @param _period The duration (in seconds) for which tokens are locked
     * @return The multiplier for this staking period
     *         Ex : 20000 = x2
     */
    function getStakePeriodMultiplier(uint256 _period)
        external
        returns (uint256);

    /**
     * @notice Get staking infos of a user
     * @param _user The user address for which to get staking infos
     * @return The staking infos of the user
     */
    function getUserInfo(address _user)
        external
        view
        returns (FeeDiscountStorage.UserInfo memory);
}
