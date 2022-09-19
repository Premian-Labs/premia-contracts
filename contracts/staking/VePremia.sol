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

    function _beforeUnstake(address user, uint256 amount) internal override {
        uint256 votingPowerUnstaked = _calculateUserPower(
            amount,
            PremiaStakingStorage.layout().userInfo[user].stakePeriod
        );

        _subtractExtraUserVotes(
            VePremiaStorage.layout(),
            user,
            votingPowerUnstaked
        );
    }

    /**
     * @notice subtract user votes, starting from the end of the list, if not enough voting power is left after amountUnstaked is unstaked
     */
    function _subtractExtraUserVotes(
        VePremiaStorage.Layout storage l,
        address user,
        uint256 amountUnstaked
    ) internal {
        uint256 votingPower = _calculateUserPower(
            _balanceOf(user),
            PremiaStakingStorage.layout().userInfo[user].stakePeriod
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

            emit RemoveVote(user, vote.version, vote.target, votesRemoved);

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
    function getPoolVotes(
        VePremiaStorage.VoteVersion version,
        bytes memory target
    ) external view returns (uint256) {
        return VePremiaStorage.layout().votes[version][target];
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

        uint256 balance = _balanceOf(msg.sender);
        uint256 userVotingPower = _calculateUserPower(
            balance,
            PremiaStakingStorage.layout().userInfo[msg.sender].stakePeriod
        );

        VePremiaStorage.Vote[] storage voteStorage = l.userVotes[msg.sender];

        // Remove previous votes
        for (uint256 i = voteStorage.length; i > 0; ) {
            VePremiaStorage.Vote memory vote = voteStorage[--i];

            l.votes[vote.version][vote.target] -= vote.amount;
            emit RemoveVote(msg.sender, vote.version, vote.target, vote.amount);

            voteStorage.pop();
        }

        // Cast new votes
        uint256 votingPowerUsed = 0;
        for (uint256 i = 0; i < votes.length; i++) {
            VePremiaStorage.Vote memory vote = votes[i];

            votingPowerUsed += votes[i].amount;
            require(
                votingPowerUsed <= userVotingPower,
                "not enough voting power"
            );

            voteStorage.push(votes[i]);
            l.votes[vote.version][vote.target] += vote.amount;

            emit AddVote(msg.sender, vote.version, vote.target, vote.amount);
        }
    }
}
