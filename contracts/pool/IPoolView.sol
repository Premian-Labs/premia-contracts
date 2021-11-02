// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {PoolStorage} from "./PoolStorage.sol";

interface IPoolView {
    function getFeeReceiverAddress() external view returns (address);

    function getPoolSettings()
        external
        view
        returns (PoolStorage.PoolSettings memory);

    function getTokenIds() external view returns (uint256[] memory);

    function getCLevel64x64(bool isCall) external view returns (int128);

    function getSteepness64x64(bool isCall) external view returns (int128);

    function getPrice(uint256 timestamp) external view returns (int128);

    function getParametersForTokenId(uint256 tokenId)
        external
        pure
        returns (
            PoolStorage.TokenType,
            uint64,
            int128
        );

    function getMinimumAmounts()
        external
        view
        returns (uint256 minCallTokenAmount, uint256 minPutTokenAmount);

    function getCapAmounts()
        external
        view
        returns (uint256 callTokenCapAmount, uint256 putTokenCapAmount);

    function getUserTVL(address user)
        external
        view
        returns (uint256 underlyingTVL, uint256 baseTVL);

    function getTotalTVL()
        external
        view
        returns (uint256 underlyingTVL, uint256 baseTVL);

    function getPremiaMining() external view returns (address);

    function getDivestmentTimestamps(address account)
        external
        view
        returns (
            uint256 callDivestmentTimestamp,
            uint256 putDivestmentTimestamp
        );

    function uri(uint256 tokenId) external view returns (string memory);
}
