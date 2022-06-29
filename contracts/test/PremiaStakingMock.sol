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

    function getUnderlyingAmount(uint256 amount)
        external
        view
        returns (uint256)
    {
        return (amount * _getXPremiaToPremiaRatio()) / 1e18;
    }

    function _send(
        address from,
        uint16 dstChainId,
        bytes memory,
        uint256 amount,
        address payable,
        address,
        bytes memory
    ) internal override {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        uint256 underlyingAmount = (amount * _getXPremiaToPremiaRatio()) / 1e18;

        bytes memory toAddress = abi.encodePacked(from);
        _debitFrom(from, dstChainId, toAddress, amount);

        if (underlyingAmount < l.debt) {
            l.debt -= underlyingAmount;
        } else {
            l.reserved += underlyingAmount - l.debt;
            l.debt = 0;
        }

        emit BridgedOut(from, underlyingAmount, amount);
    }

    function creditTo(address toAddress, uint256 underlyingAmount) external {
        _creditTo(0, toAddress, underlyingAmount);
    }
}
