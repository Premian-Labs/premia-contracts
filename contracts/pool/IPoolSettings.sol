// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @notice Administrative Pool interface for parameter tuning
 */
interface IPoolSettings {
    /**
     * @notice set pool deposit caps
     * @param basePoolCap put pool cap
     * @param underlyingPoolCap call pool cap
     */
    function setPoolCaps(uint256 basePoolCap, uint256 underlyingPoolCap)
        external;

    /**
     * @notice set minimum liquidity interval sizes
     * @param baseMinimum minimum base currency interval size
     * @param underlyingMinimum minimum underlying currency interval size
     */
    function setMinimumAmounts(uint256 baseMinimum, uint256 underlyingMinimum)
        external;

    /**
     * @notice set steepness of internal C-Level update multiplier
     * @param steepness64x64 64x64 fixed point representation of steepness
     * @param isCallPool true for call, false for put
     */
    function setSteepness64x64(int128 steepness64x64, bool isCallPool) external;

    /**
     * @notice set Pool C-Level
     * @param cLevel64x64 64x46 fixed point representation of C-Level
     * @param isCallPool true for call, false for put
     */
    function setCLevel64x64(int128 cLevel64x64, bool isCallPool) external;
}
