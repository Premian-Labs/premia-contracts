// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolSettings {
    function setPoolCaps(uint256 basePoolCap, uint256 underlyingPoolCap)
        external;

    function setMinimumAmounts(uint256 baseMinimum, uint256 underlyingMinimum)
        external;

    function setSteepness64x64(int128 steepness64x64) external;

    function setCLevel64x64(int128 cLevel64x64, bool isCallPool) external;
}
