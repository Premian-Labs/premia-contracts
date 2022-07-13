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
        address rewardToken,
        address exchangeHelper
    ) PremiaStaking(lzEndpoint, premia, rewardToken, exchangeHelper) {}

    function _beforeStake(uint256 amount, uint64 period) internal override {
        PremiaStakingStorage.UserInfo memory userInfo = PremiaStakingStorage
            .layout()
            .userInfo[msg.sender];

        VePremiaStorage.Layout storage l = VePremiaStorage.layout();

        uint256 balance = _balanceOf(msg.sender);

        uint256 currentPower = _calculateUserPower(
            balance,
            userInfo.stakePeriod
        );

        uint256 newPower = _calculateUserPower(amount + balance, period);

        if (newPower < currentPower) {
            // We can have newPower < currentPower if user add a small amount with a smaller stake period
            _subtractExtraUserVotes(l, msg.sender, currentPower - newPower);
        }
    }

    function _beforeUnstake(uint256 amount) internal override {
        PremiaStakingStorage.UserInfo memory userInfo = PremiaStakingStorage
            .layout()
            .userInfo[msg.sender];

        VePremiaStorage.Layout storage l = VePremiaStorage.layout();

        uint256 votingPowerUnstaked = _calculateUserPower(
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

        uint256 votingPower = _calculateUserPower(
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
            VePremiaStorage.Vote memory vote = l.userVotes[user][i - 1];

            uint256 votesRemoved;
            if (toSubtract <= vote.amount) {
                votesRemoved = toSubtract;
                l.userVotes[user][i - 1].amount -= toSubtract;
            } else {
                votesRemoved = vote.amount;
                l.userVotes[user].pop();
            }

            toSubtract -= votesRemoved;

            emit RemoveVote(
                user,
                vote.poolAddress,
                vote.isCallPool,
                votesRemoved
            );

            if (toSubtract == 0) return;
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
        uint256 userVotingPower = _calculateUserPower(
            balance,
            userInfo.stakePeriod
        );

        // Remove previous votes
        for (uint256 i = 0; i < l.userVotes[msg.sender].length; i++) {
            VePremiaStorage.Vote memory vote = l.userVotes[msg.sender][i];

            l.votes[vote.poolAddress][vote.isCallPool] -= vote.amount;
            emit RemoveVote(
                msg.sender,
                vote.poolAddress,
                vote.isCallPool,
                vote.amount
            );
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

            emit AddVote(
                msg.sender,
                vote.poolAddress,
                vote.isCallPool,
                vote.amount
            );
        }
    }
}
