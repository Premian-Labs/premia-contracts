// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {FeeDiscount} from "./FeeDiscount.sol";
import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";
import {VePremiaStorage} from "./VePremiaStorage.sol";

/**
 * @author Premia
 * @title A contract allowing you to use your locked Premia as voting power for mining weights
 */
contract VePremia is FeeDiscount {
    constructor(address xPremia) FeeDiscount(xPremia) {}

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

        if (newPower > currentPower) {
            l.totalVotingPower += newPower - currentPower;
        } else {
            // We can have newPower < currentPower if user add a small amount with a smaller stake period
            l.totalVotingPower -= currentPower - newPower;
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
        l.totalVotingPower -= votingPowerUnstaked;
    }

    function _calculateVotingPower(uint256 amount, uint256 period)
        internal
        pure
        returns (uint256)
    {
        return
            (amount * _getStakePeriodMultiplier(period)) / INVERSE_BASIS_POINT;
    }

    function getTotalVotingPower() external view returns (uint256) {
        return VePremiaStorage.layout().totalVotingPower;
    }

    function getUserVotingPower(address user) external view returns (uint256) {
        FeeDiscountStorage.UserInfo memory userInfo = FeeDiscountStorage
            .layout()
            .userInfo[user];

        return _calculateVotingPower(userInfo.balance, userInfo.stakePeriod);
    }
}
