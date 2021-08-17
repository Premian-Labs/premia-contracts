// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPremiaBondingCurveUpgrade {
    function initialize(
        uint256 _premiaBalance,
        uint256 _ethBalance,
        uint256 _soldAmount
    ) external payable;
}
