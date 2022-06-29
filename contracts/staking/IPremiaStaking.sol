// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";

interface IPremiaStaking {
    event Deposit(address indexed user, uint256 amount);
    event StartWithdrawal(
        address indexed user,
        uint256 premiaAmount,
        uint256 startDate
    );
    event Withdrawal(address indexed user, uint256 amount);

    event RewardsAdded(uint256 amount);

    event BridgedIn(
        address indexed user,
        uint256 underlyingAmount,
        uint256 xPremiaAmount
    );
    event BridgedOut(
        address indexed user,
        uint256 underlyingAmount,
        uint256 xPremiaAmount
    );

    event Staked(
        address indexed user,
        uint256 amount,
        uint256 stakePeriod,
        uint256 lockedUntil
    );
    event Unstaked(address indexed user, uint256 amount);

    struct StakeLevel {
        uint256 amount; // Amount to stake
        uint256 discount; // Discount when amount is reached
    }

    /**
     * @notice add premia tokens as available tokens to be distributed as rewards
     * @param amount amount of premia tokens to add as rewards
     */
    function addRewards(uint256 amount) external;

    /**
     * @notice get amount of tokens that have not yet been distributed as rewards
     * @return amount of tokens not yet distributed as rewards
     */
    function getAvailableRewards() external view returns (uint256);

    /**
     * @notice get pending amount of tokens to be distributed as rewards to stakers
     * @return amount of tokens pending to be distributed as rewards
     */
    function getPendingRewards() external view returns (uint256);

    /**
     * @notice get current withdrawal delay
     * @return withdrawal delay
     */
    function getWithdrawalDelay() external view returns (uint256);

    /**
     * @notice set current withdrawal delay
     * @param delay withdrawal delay
     */
    function setWithdrawalDelay(uint256 delay) external;

    /**
     * @notice get debt due to tokens bridged to other chains
     * @return underlying debt due to tokens bridged from other chains
     */
    function getDebt() external view returns (uint256);

    /**
     * @notice get reserved amount due to tokens bridged to other chains
     * @return underlying reserved due to tokens bridged to other chains
     */
    function getReserved() external view returns (uint256);

    /**
     * @notice get pending withdrawal data of a user
     * @return amount pending withdrawal amount
     * @return startDate start timestamp of withdrawal
     * @return unlockDate timestamp at which withdrawal becomes available
     */
    function getPendingWithdrawal(address user)
        external
        view
        returns (
            uint256 amount,
            uint256 startDate,
            uint256 unlockDate
        );

    /**
     * @notice get the amount of PREMIA staked (subtracting all pending withdrawals)
     * @return amount of PREMIA staked
     */
    function getStakedPremiaAmount() external view returns (uint256);

    /**
     * @notice get the amount of PREMIA available for withdrawal (Ignoring reserved and debt)
     * @return amount of PREMIA available for withdrawal
     */
    function getAvailablePremiaAmount() external view returns (uint256);

    /**
     * @notice Stake using IERC2612 permit
     * @param amount The amount of xPremia to stake
     * @param period The lockup period (in seconds)
     * @param deadline Deadline after which permit will fail
     * @param v V
     * @param r R
     * @param s S
     */
    function stakeWithPermit(
        uint256 amount,
        uint256 period,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Lockup xPremia for protocol fee discounts
     *          Longer period of locking will apply a multiplier on the amount staked, in the fee discount calculation
     * @param amount The amount of xPremia to stake
     * @param period The lockup period (in seconds)
     */
    function stake(uint256 amount, uint256 period) external;

    /**
     * @notice Harvest rewards
     * @param compound Whether to compound rewards or to withdraw to wallet. Compounding will swap rewards to PREMIA, and add them to the stake without modifying the lock
     */
    function collectRewards(bool compound) external;

    /**
     * @notice Get pending rewards amount, including pending pool update
     * @param user User for which to calculate pending rewards
     * @return amount of pending rewards
     */
    function getPendingUserRewards(address user)
        external
        view
        returns (uint256);

    /**
     * @notice Initiate the withdrawal process by burning xPremia, starting the delay period
     * @param amount quantity of xPremia to unstake
     */
    function startWithdraw(uint256 amount) external;

    /**
     * @notice Withdraw underlying premia
     */
    function withdraw() external;

    //////////
    // View //
    //////////

    /**
     * Calculate the stake amount of a user, after applying the bonus from the lockup period chosen
     * @param user The user from which to query the stake amount
     * @return The user stake amount after applying the bonus
     */
    function getStakeAmountWithBonus(address user)
        external
        view
        returns (uint256);

    /**
     * @notice Calculate the % of fee discount for user, based on his stake
     * @param user The _user for which the discount is for
     * @return Percentage of protocol fee discount (in basis point)
     *         Ex : 1000 = 10% fee discount
     */
    function getDiscount(address user) external view returns (uint256);

    /**
     * @notice Get stake levels
     * @return Stake levels
     *         Ex : 2500 = -25%
     */
    function getStakeLevels() external returns (StakeLevel[] memory);

    /**
     * @notice Get stake period multiplier
     * @param period The duration (in seconds) for which tokens are locked
     * @return The multiplier for this staking period
     *         Ex : 20000 = x2
     */
    function getStakePeriodMultiplier(uint256 period)
        external
        returns (uint256);

    /**
     * @notice Get staking infos of a user
     * @param user The user address for which to get staking infos
     * @return The staking infos of the user
     */
    function getUserInfo(address user)
        external
        view
        returns (PremiaStakingStorage.UserInfo memory);
}
