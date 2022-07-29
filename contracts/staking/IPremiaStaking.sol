// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";

interface IPremiaStaking {
    event Stake(
        address indexed user,
        uint256 amount,
        uint64 stakePeriod,
        uint64 lockedUntil
    );

    event Unstake(
        address indexed user,
        uint256 amount,
        uint256 fee,
        uint256 startDate
    );

    event Harvest(address indexed user, uint256 amount);

    event EarlyUnstakeRewardCollected(address indexed user, uint256 amount);

    event Compound(
        address indexed user,
        uint256 tokenAmount,
        uint256 premiaAmount
    );

    event Withdraw(address indexed user, uint256 amount);

    event RewardsAdded(uint256 amount);

    struct StakeLevel {
        uint256 amount; // Amount to stake
        uint256 discount; // Discount when amount is reached
    }

    event BridgeLock(
        address indexed user,
        uint64 stakePeriod,
        uint64 lockedUntil
    );

    /**
     * @notice add premia tokens as available tokens to be distributed as rewards
     * @param amount amount of premia tokens to add as rewards
     */
    function addRewards(uint256 amount) external;

    /**
     * @notice get amount of tokens that have not yet been distributed as rewards
     * @return rewards amount of tokens not yet distributed as rewards
     * @return unstakeRewards amount of PREMIA not yet claimed from early unstake fees
     */
    function getAvailableRewards()
        external
        view
        returns (uint256 rewards, uint256 unstakeRewards);

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
     * @notice get the amount of PREMIA available for withdrawal
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
        uint64 period,
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
    function stake(uint256 amount, uint64 period) external;

    /**
     * @notice Harvest rewards directly to user wallet
     */
    function harvest() external;

    /**
     * @notice Add pending rewards to current stake without impacting current lock after swapping rewards to PREMIA tokens
     * @param callee exchange address to call to execute the trade.
     * @param data calldata to execute the trade
     * @param amountOutMin minimum amount taken from the trade.
     * @return amountCredited amount of tokenOut we got from the trade.
     */
    function compound(
        address callee,
        bytes memory data,
        uint256 amountOutMin
    ) external returns (uint256 amountCredited);

    /**
     * @notice Get pending rewards amount, including pending pool update
     * @param user User for which to calculate pending rewards
     * @return reward amount of pending rewards from protocol fees (in REWARD_TOKEN)
     * @return unstakeReward amount of pending rewards from early unstake fees (in PREMIA)
     */
    function getPendingUserRewards(address user)
        external
        view
        returns (uint256 reward, uint256 unstakeReward);

    /**
     * @notice unstake tokens before end of the lock period, for a fee
     * @param amount the amount of vePremia to unstake
     */
    function earlyUnstake(uint256 amount) external;

    /**
     * @notice get early unstake fee for given user
     * @param user address of the user
     * @return feePercentage % fee to pay for early unstake (1e4 = 100%)
     */
    function getEarlyUnstakeFee(address user)
        external
        view
        returns (uint256 feePercentage);

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
    function getUserPower(address user) external view returns (uint256);

    /**
     * Return the total power across all users (applying the bonus from lockup period chosen)
     * @return The total power across all users
     */
    function getTotalPower() external view returns (uint256);

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
