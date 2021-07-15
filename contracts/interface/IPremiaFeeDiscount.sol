// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPremiaFeeDiscount {
    struct UserInfo {
        uint256 balance; // Balance staked by user
        uint64 stakePeriod; // Stake period selected by user
        uint64 lockedUntil; // Timestamp at which the lock ends
    }

    function userInfo(address _user) external view returns (UserInfo memory);

    function getDiscount(address _user) external view returns (uint256);
}
