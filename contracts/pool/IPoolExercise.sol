// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolExercise {
    function processExpired(uint256 longTokenId, uint256 contractSize) external;
}
