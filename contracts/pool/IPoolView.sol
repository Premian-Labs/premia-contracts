// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolView {
    function getTokenIds() external view returns (uint256[] memory);
}
