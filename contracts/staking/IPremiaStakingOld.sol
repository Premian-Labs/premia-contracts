// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPremiaStakingOld {
    /**
     * @notice stake PREMIA using IERC2612 permit
     * @param amount quantity of PREMIA to stake
     * @param deadline timestamp after which permit will fail
     * @param v signature "v" value
     * @param r signature "r" value
     * @param s signature "s" value
     */
    function enterWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice stake PREMIA in exchange for xPremia
     * @param amount quantity of PREMIA to stake
     */
    function enter(uint256 amount) external;

    /**
     * @notice burn xPremia in exchange for staked PREMIA
     * @param amount quantity of xPremia to unstake
     */
    function leave(uint256 amount) external;
}
