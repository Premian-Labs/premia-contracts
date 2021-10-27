// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPoolExercise {
    function exerciseFrom(
        address holder,
        uint256 longTokenId,
        uint256 contractSize
    ) external;

    function processExpired(uint256 longTokenId, uint256 contractSize) external;
}
