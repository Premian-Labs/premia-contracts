// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {VolatilitySurfaceOracleStorage} from "./VolatilitySurfaceOracleStorage.sol";

interface IVolatilitySurfaceOracle {
    function getWhitelistedRelayers() external view returns (address[] memory);

    function getVolatilitySurface(address baseToken, address underlyingToken)
        external
        view
        returns (VolatilitySurfaceOracleStorage.Update memory);

    function getVolatilitySurfaceCoefficientsUnpacked(
        address baseToken,
        address underlyingToken,
        bool isCall
    ) external view returns (int256[] memory);

    function getTimeToMaturity64x64(uint64 maturity)
        external
        view
        returns (int128);

    function getAnnualizedVolatility64x64(
        address baseToken,
        address underlyingToken,
        int128 moneyness64x64,
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
