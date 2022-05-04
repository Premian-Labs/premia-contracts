// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PremiaStakingWithFeeDiscount} from "./PremiaStakingWithFeeDiscount.sol";
import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";
import {VePremiaStorage} from "./VePremiaStorage.sol";
import {IVePremia} from "./IVePremia.sol";

/**
 * @author Premia
 * @title A contract allowing you to use your locked Premia as voting power for mining weights
 */
contract VePremia is IVePremia, PremiaStakingWithFeeDiscount {
    constructor(
        address premia,
        address oldFeeDiscount,
        address oldStaking
    ) PremiaStakingWithFeeDiscount(premia, oldFeeDiscount, oldStaking) {}

    function _beforeStake(uint256 amount, uint256 period) internal override {
        FeeDiscountStorage.UserInfo memory userInfo = FeeDiscountStorage
            .layout()
            .userInfo[msg.sender];

        VePremiaStorage.Layout storage l = VePremiaStorage.layout();

        uint256 currentPower = _calculateVotingPower(
            userInfo.balance,
            userInfo.stakePeriod
        );

        uint256 newPower = _calculateVotingPower(
            amount + userInfo.balance,
            period
        );

        if (newPower >= currentPower) {
            l.totalVotingPower += newPower - currentPower;
        } else {
            // We can have newPower < currentPower if user add a small amount with a smaller stake period
            _subtractExtraUserVotes(l, msg.sender, currentPower - newPower);
        }
    }

    function _beforeUnstake(uint256 amount) internal override {
        FeeDiscountStorage.UserInfo memory userInfo = FeeDiscountStorage
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
        FeeDiscountStorage.UserInfo memory userInfo = FeeDiscountStorage
            .layout()
            .userInfo[user];

        uint256 votingPower = _calculateVotingPower(
            userInfo.balance,
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
        for (uint256 i = l.userVotes[user].length + 1; i > 0; i--) {
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
    function getUserVotingPower(address user) external view returns (uint256) {
        FeeDiscountStorage.UserInfo memory userInfo = FeeDiscountStorage
            .layout()
            .userInfo[user];

        return _calculateVotingPower(userInfo.balance, userInfo.stakePeriod);
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

        FeeDiscountStorage.UserInfo memory userInfo = FeeDiscountStorage
            .layout()
            .userInfo[msg.sender];

        uint256 userVotingPower = _calculateVotingPower(
            userInfo.balance,
            userInfo.stakePeriod
        );

        // Remove previous votes
        for (uint256 i = 0; i < l.userVotes[msg.sender].length; i++) {
            VePremiaStorage.Vote memory vote = l.userVotes[msg.sender][i];

            l.votes[vote.chainId][vote.poolAddress][vote.isCallPool] -= vote
                .amount;
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
            l.votes[vote.chainId][vote.poolAddress][vote.isCallPool] += vote
                .amount;
        }

        // ToDo : Handle pool updates
    }
}
