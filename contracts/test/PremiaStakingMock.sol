// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PremiaStaking} from "../staking/PremiaStaking.sol";

contract PremiaStakingMock is PremiaStaking {
    constructor(address premia) PremiaStaking(premia) {}

    function decay(
        uint256 pendingRewards,
        uint256 oldTimestamp,
        uint256 newTimestamp
    ) external pure returns (uint256) {
        return _decay(pendingRewards, oldTimestamp, newTimestamp);
    }
}
