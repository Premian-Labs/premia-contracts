// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PoolStorage} from "./PoolStorage.sol";

interface IPoolView {
    function getPoolSettings()
        external
        view
        returns (PoolStorage.PoolSettings memory);

    function getTokenIds() external view returns (uint256[] memory);

    function getCLevel64x64(bool isCall) external view returns (int128);

    function getEmaLogReturns64x64() external view returns (int128);

    function getEmaVarianceAnnualized64x64() external view returns (int128);

    function getPrice(uint256 timestamp) external view returns (int128);

    function getParametersForTokenId(uint256 tokenId)
        external
        pure
        returns (
            PoolStorage.TokenType,
            uint64,
            int128
        );
}
