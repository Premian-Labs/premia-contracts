// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IVolatilitySurfaceOracle {
    function getWhitelistedRelayers() external view returns (address[] memory);

    function getVolatilitySurface64x64(
        address baseToken,
        address underlyingToken,
        bool isCall
    ) external view returns (int128[] memory);

    function getLastUpdateTimestamp(
        address baseToken,
        address underlyingToken,
        bool isCall
    ) external view returns (uint256);

    function getTimeToMaturity64x64(uint64 maturity)
        external
        view
        returns (int128);

    function getAnnualizedVolatility64x64(
        address baseToken,
        address underlyingToken,
        int128 strikeToSpotRatio,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (int128);

    function getBlackScholesPrice64x64(
        address baseToken,
        address underlyingToken,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (int128);

    function getBlackScholesPrice(
        address baseToken,
        address underlyingToken,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (uint256);
}
