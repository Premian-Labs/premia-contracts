// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PremiaStaking, PremiaStakingStorage} from "../staking/PremiaStaking.sol";

contract PremiaStakingMock is PremiaStaking {
    constructor(
        address lzEndpoint,
        address premia,
        address rewardToken
    ) PremiaStaking(lzEndpoint, premia, rewardToken) {}

    function decay(
        uint256 pendingRewards,
        uint256 oldTimestamp,
        uint256 newTimestamp
    ) external pure returns (uint256) {
        return _decay(pendingRewards, oldTimestamp, newTimestamp);
    }

    function _send(
        address from,
        uint16 dstChainId,
        bytes memory,
        uint256 amount,
        address payable,
        address,
        bytes memory
    ) internal virtual override {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage user = l.userInfo[from];

        uint256 balance = _balanceOf(from);
        uint256 reward = user.reward +
            _calculateReward(l.accRewardPerShare, balance, user.rewardDebt);

        bytes memory toAddress = abi.encodePacked(from);
        _debitFrom(from, dstChainId, toAddress, amount);

        user.rewardDebt = (balance - amount) * l.accRewardPerShare;
        user.reward += reward;

        emit SendToChain(from, dstChainId, toAddress, amount, 0);
    }

    function creditTo(address toAddress, uint256 amount) external {
        _creditTo(0, toAddress, amount);
    }
}
