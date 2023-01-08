// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PremiaStaking} from "./PremiaStaking.sol";
import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";
import {VxPremiaStorage} from "./VxPremiaStorage.sol";
import {IVxPremia} from "./IVxPremia.sol";

/**
 * @author Premia
 * @title A contract allowing you to use your locked Premia as voting power for mining weights
 */
contract VxPremia is IVxPremia, PremiaStaking {
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
            VxPremiaStorage.layout(),
            user,
            votingPowerUnstaked
        );
    }

    /**
     * @notice subtract user votes, starting from the end of the list, if not enough voting power is left after amountUnstaked is unstaked
     */
    function _subtractExtraUserVotes(
        VxPremiaStorage.Layout storage l,
        address user,
        uint256 amountUnstaked
    ) internal {
        uint256 votingPower = _calculateUserPower(
            _balanceOf(user),
            PremiaStakingStorage.layout().userInfo[user].stakePeriod
        );
        uint256 votingPowerUsed = _calculateUserVotingPowerUsed(user);
        uint256 votingPowerLeftAfterUnstake = votingPower - amountUnstaked;

        unchecked {
            if (votingPowerUsed > votingPowerLeftAfterUnstake) {
                _subtractUserVotes(
                    l,
                    user,
                    votingPowerUsed - votingPowerLeftAfterUnstake
                );
            }
        }
    }

    /**
     * @notice subtract user votes, starting from the end of the list
     */
    function _subtractUserVotes(
        VxPremiaStorage.Layout storage l,
        address user,
        uint256 amount
    ) internal {
        uint256 toSubtract = amount;
        VxPremiaStorage.Vote[] storage userVotes = l.userVotes[user];

        unchecked {
            for (uint256 i = userVotes.length; i > 0; ) {
                VxPremiaStorage.Vote memory vote = userVotes[--i];

                uint256 votesRemoved;

                if (toSubtract <= vote.amount) {
                    votesRemoved = toSubtract;
                    userVotes[i].amount -= toSubtract;
                } else {
                    votesRemoved = vote.amount;
                    userVotes.pop();
                }

                toSubtract -= votesRemoved;

                l.votes[vote.version][vote.target] -= votesRemoved;
                emit RemoveVote(user, vote.version, vote.target, votesRemoved);

                if (toSubtract == 0) break;
            }
        }
    }

    function _calculateUserVotingPowerUsed(
        address user
    ) internal view returns (uint256 votingPowerUsed) {
        VxPremiaStorage.Vote[] memory userVotes = VxPremiaStorage
            .layout()
            .userVotes[user];

        unchecked {
            for (uint256 i = 0; i < userVotes.length; i++) {
                votingPowerUsed += userVotes[i].amount;
            }
        }
    }

    /**
     * @inheritdoc IVxPremia
     */
    function getPoolVotes(
        VxPremiaStorage.VoteVersion version,
        bytes memory target
    ) external view returns (uint256) {
        return VxPremiaStorage.layout().votes[version][target];
    }

    /**
     * @inheritdoc IVxPremia
     */
    function getUserVotes(
        address user
    ) external view returns (VxPremiaStorage.Vote[] memory) {
        return VxPremiaStorage.layout().userVotes[user];
    }

    /**
     * @inheritdoc IVxPremia
     */
    function castVotes(VxPremiaStorage.Vote[] memory votes) external {
        VxPremiaStorage.Layout storage l = VxPremiaStorage.layout();

        uint256 userVotingPower = _calculateUserPower(
            _balanceOf(msg.sender),
            PremiaStakingStorage.layout().userInfo[msg.sender].stakePeriod
        );

        VxPremiaStorage.Vote[] storage userVotes = l.userVotes[msg.sender];

        // Remove previous votes
        for (uint256 i = userVotes.length; i > 0; ) {
            VxPremiaStorage.Vote memory vote = userVotes[--i];

            l.votes[vote.version][vote.target] -= vote.amount;
            emit RemoveVote(msg.sender, vote.version, vote.target, vote.amount);

            userVotes.pop();
        }

        // Cast new votes
        uint256 votingPowerUsed = 0;
        for (uint256 i = 0; i < votes.length; i++) {
            VxPremiaStorage.Vote memory vote = votes[i];

            votingPowerUsed += votes[i].amount;
            if (votingPowerUsed > userVotingPower)
                revert VxPremia__NotEnoughVotingPower();

            userVotes.push(votes[i]);
            l.votes[vote.version][vote.target] += vote.amount;

            emit AddVote(msg.sender, vote.version, vote.target, vote.amount);
        }
    }
}
