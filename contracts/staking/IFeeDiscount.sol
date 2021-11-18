// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IFeeDiscount {
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
     * @notice Get number of stake levels
     * @return The amount of stake levels
     */
    function stakeLevelsLength() external view returns (uint256);

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
}
