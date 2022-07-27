// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @notice Administrative Pool interface for parameter tuning
 */
interface IPoolSettings {
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

    /**
     * @notice set APY fee amount
     * @param feeApy64x64 64x64 fixed point representation of APY fee
     */
    function setFeeApy64x64(int128 feeApy64x64) external;

    /**
     * @notice set spot price offset rate to account for Chainlink price feed lag
     * @param spotOffset64x64 64x64 fixed point representation of spot price offset
     */
    function setSpotOffset64x64(int128 spotOffset64x64) external;
}
