// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PremiaStaking} from "./PremiaStaking.sol";
import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";
import {VePremiaStorage} from "./VePremiaStorage.sol";
import {IVePremia} from "./IVePremia.sol";

/**
 * @author Premia
 * @title A contract allowing you to use your locked Premia as voting power for mining weights
 */
contract VePremia is IVePremia, PremiaStaking {
    constructor(
        address lzEndpoint,
        address premia,
        address rewardToken
    ) PremiaStaking(lzEndpoint, premia, rewardToken) {}

    /**
     * @inheritdoc IVePremia
     */
    function earlyUnstake(uint256 amount) external {
        // ToDo : Update to work with USDC rewards
        _beforeUnstake(amount);

        // ToDo : Update rewards

        uint256 feePercentage = _getEarlyUnstakeFee(msg.sender);

        _burn(msg.sender, amount);

        uint256 fee = (amount * feePercentage) / 1e4;
        if (fee > 0) {
            _addRewards(fee);
        }

        // ToDo : Withdrawal delay ?

        // _transferXPremia(address(this), msg.sender, amount - fee); // ToDo : update

        emit Unstake(msg.sender, amount);
        emit EarlyUnstake(msg.sender, amount, fee);
    }

    /**
     * @inheritdoc IVePremia
     */
    function getEarlyUnstakeFee(address user)
        external
        view
        returns (uint256 feePercentage)
    {
        return _getEarlyUnstakeFee(user);
    }

    function _getEarlyUnstakeFee(address user)
        internal
        view
        returns (uint256 feePercentage)
    {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[user];

        require(u.lockedUntil > block.timestamp, "Not locked");
        uint256 lockLeft = u.lockedUntil - block.timestamp;

        feePercentage = (lockLeft * 2500) / 365 days; // 25% fee per year left
        if (feePercentage > 7500) {
            feePercentage = 7500; // Capped at 75%
        }
    }

    function _beforeStake(uint256 amount, uint256 period) internal override {
        PremiaStakingStorage.UserInfo memory userInfo = PremiaStakingStorage
            .layout()
            .userInfo[msg.sender];

        VePremiaStorage.Layout storage l = VePremiaStorage.layout();

        uint256 balance = _balanceOf(msg.sender);

        uint256 currentPower = _calculateVotingPower(
            balance,
            userInfo.stakePeriod
        );

        uint256 newPower = _calculateVotingPower(amount + balance, period);

        if (newPower >= currentPower) {
            l.totalVotingPower += newPower - currentPower;
        } else {
            // We can have newPower < currentPower if user add a small amount with a smaller stake period
            _subtractExtraUserVotes(l, msg.sender, currentPower - newPower);
        }
    }

    function _beforeUnstake(uint256 amount) internal override {
        PremiaStakingStorage.UserInfo memory userInfo = PremiaStakingStorage
            .layout()
            .userInfo[msg.sender];

        VePremiaStorage.Layout storage l = VePremiaStorage.layout();

        uint256 votingPowerUnstaked = _calculateVotingPower(
            amount,
            userInfo.stakePeriod
        );

        _subtractExtraUserVotes(l, msg.sender, votingPowerUnstaked);
    }

    /**
     * @notice subtract user votes, starting from the end of the list, if not enough voting power is left after amountUnstaked is unstaked
     */
    function _subtractExtraUserVotes(
        VePremiaStorage.Layout storage l,
        address user,
        uint256 amountUnstaked
    ) internal {
        PremiaStakingStorage.UserInfo memory userInfo = PremiaStakingStorage
            .layout()
            .userInfo[user];

        uint256 balance = _balanceOf(user); // ToDo : Directly pass new balance ?

        uint256 votingPower = _calculateVotingPower(
            balance,
            userInfo.stakePeriod
        );
        uint256 votingPowerUsed = _calculateUserVotingPowerUsed(user);
        uint256 votingPowerLeftAfterUnstake = votingPower - amountUnstaked;

        if (votingPowerUsed > votingPowerLeftAfterUnstake) {
            _subtractUserVotes(
                l,
                user,
                votingPowerUsed - votingPowerLeftAfterUnstake
            );
        }

        l.totalVotingPower -= amountUnstaked;
    }

    /**
     * @notice subtract user votes, starting from the end of the list
     */
    function _subtractUserVotes(
        VePremiaStorage.Layout storage l,
        address user,
        uint256 amount
    ) internal {
        uint256 toSubtract = amount;
        for (uint256 i = l.userVotes[user].length; i > 0; i--) {
            if (toSubtract <= l.userVotes[user][i - 1].amount) {
                l.userVotes[user][i - 1].amount -= toSubtract;
                return;
            }

            toSubtract -= l.userVotes[user][i - 1].amount;
            l.userVotes[user].pop();
        }
    }

    function _calculateUserVotingPowerUsed(address user)
        internal
        view
        returns (uint256 votingPowerUsed)
    {
        VePremiaStorage.Vote[] memory userVotes = VePremiaStorage
            .layout()
            .userVotes[user];

        for (uint256 i = 0; i < userVotes.length; i++) {
            votingPowerUsed += userVotes[i].amount;
        }
    }

    function _calculateVotingPower(uint256 amount, uint256 period)
        internal
        pure
        returns (uint256)
    {
        return
            (amount * _getStakePeriodMultiplier(period)) / INVERSE_BASIS_POINT;
    }

    /**
     * @inheritdoc IVePremia
     */
    function getTotalVotingPower() external view returns (uint256) {
        return VePremiaStorage.layout().totalVotingPower;
    }

    /**
     * @inheritdoc IVePremia
     */
    function getPoolVotes(address pool, bool isCallPool)
        external
        view
        returns (uint256)
    {
        VePremiaStorage.Layout storage l = VePremiaStorage.layout();
        return l.votes[pool][isCallPool];
    }

    /**
     * @inheritdoc IVePremia
     */
    function getUserVotingPower(address user) external view returns (uint256) {
        PremiaStakingStorage.UserInfo memory userInfo = PremiaStakingStorage
            .layout()
            .userInfo[user];

        uint256 balance = _balanceOf(user);
        return _calculateVotingPower(balance, userInfo.stakePeriod);
    }

    /**
     * @inheritdoc IVePremia
     */
    function getUserVotes(address user)
        external
        view
        returns (VePremiaStorage.Vote[] memory)
    {
        return VePremiaStorage.layout().userVotes[user];
    }

    /**
     * @inheritdoc IVePremia
     */
    function castVotes(VePremiaStorage.Vote[] memory votes) external {
        VePremiaStorage.Layout storage l = VePremiaStorage.layout();

        PremiaStakingStorage.UserInfo memory userInfo = PremiaStakingStorage
            .layout()
            .userInfo[msg.sender];

        uint256 balance = _balanceOf(msg.sender);
        uint256 userVotingPower = _calculateVotingPower(
            balance,
            userInfo.stakePeriod
        );

        // Remove previous votes
        for (uint256 i = 0; i < l.userVotes[msg.sender].length; i++) {
            VePremiaStorage.Vote memory vote = l.userVotes[msg.sender][i];

            l.votes[vote.poolAddress][vote.isCallPool] -= vote.amount;
        }

        delete l.userVotes[msg.sender];

        // Cast new votes
        uint256 votingPowerUsed = 0;
        for (uint256 i = 0; i < votes.length; i++) {
            VePremiaStorage.Vote memory vote = votes[i];

            votingPowerUsed += votes[i].amount;
            require(
                votingPowerUsed <= userVotingPower,
                "not enough voting power"
            );

            l.userVotes[msg.sender].push(votes[i]);
            l.votes[vote.poolAddress][vote.isCallPool] += vote.amount;
        }
    }
}
