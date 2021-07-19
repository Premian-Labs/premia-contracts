// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INewPremiaFeeDiscount {
    function migrate(
        address _user,
        uint256 _amount,
        uint256 _stakePeriod,
        uint256 _lockedUntil
    ) external;
}
