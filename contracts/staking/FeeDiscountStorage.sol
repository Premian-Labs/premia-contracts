// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

library FeeDiscountStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.staking.PremiaFeeDiscount");

    struct UserInfo {
        uint256 balance; // Balance staked by user
        uint64 stakePeriod; // Stake period selected by user
        uint64 lockedUntil; // Timestamp at which the lock ends
    }

    struct StakeLevel {
        uint256 amount; // Amount to stake
        uint256 discount; // Discount when amount is reached
    }

    struct Layout {
        // User data with xPREMIA balance staked and date at which lock ends
        mapping(address => UserInfo) userInfo;
        // Available xPREMIA lockup periods with their bonus (seconds lockup => multiplier (x1 = 1e4))
        mapping(uint256 => uint256) stakePeriods;
        // List of all existing xPREMIA stake periods
        uint256[] existingStakePeriods;
        // xPREMIA staking levels
        StakeLevel[] stakeLevels;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
