// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface IPremiaBondingCurve {
    function isInitialized() external view returns(bool);
    function initialize(uint256 _startPrice) external;
}