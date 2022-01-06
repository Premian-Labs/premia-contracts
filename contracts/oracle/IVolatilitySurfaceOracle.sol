// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {VolatilitySurfaceOracleStorage} from "./VolatilitySurfaceOracleStorage.sol";

interface IVolatilitySurfaceOracle {
    /**
     * @notice Get the list of whitelisted relayers
     * @return The list of whitelisted relayers
     */
    function getWhitelistedRelayers() external view returns (address[] memory);

    /**
     * @notice Get the IV model parameters of a token pair
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @return The IV model parameters
     */
    function getParams(address base, address underlying)
        external
        view
        returns (VolatilitySurfaceOracleStorage.Update memory);

    /**
     * @notice Get unpacked IV model parameters
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @return The unpacked IV model parameters
     */
    function getParamsUnpacked(address base, address underlying)
        external
        view
        returns (int256[] memory);

    /**
     * @notice Get time to maturity in years, as a 64x64 fixed point representation
     * @param maturity Maturity timestamp
     * @return Time to maturity (in years), as a 64x64 fixed point representation
     */
    function getTimeToMaturity64x64(uint64 maturity)
        external
        view
        returns (int128);

    /**
     * @notice Get annualized volatility as a 64x64 fixed point representation
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param spot64x64 The spot, as a 64x64 fixed point representation
     * @param strike64x64 The strike, as a 64x64 fixed point representation
     * @param timeToMaturity64x64 Time to maturity (in years), as a 64x64 fixed point representation
     * @return Annualized implied volatility, as a 64x64 fixed point representation. 1 = 100%
     */
    function getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) external view returns (int128);

    /**
     * @notice Get Black Scholes price as a 64x64 fixed point representation
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param strike64x64 Strike, as a64x64 fixed point representation
     * @param spot64x64 Spot price, as a 64x64 fixed point representation
     * @param timeToMaturity64x64 Time to maturity (in years), as a 64x64 fixed point representation
     * @param isCall Whether it is for call or put
     * @return Black scholes price, as a 64x64 fixed point representation
     */
    function getBlackScholesPrice64x64(
        address base,
        address underlying,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (int128);

    /**
     * @notice Get Black Scholes price as an uint256 with 18 decimals
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param strike64x64 Strike, as a64x64 fixed point representation
     * @param spot64x64 Spot price, as a 64x64 fixed point representation
     * @param timeToMaturity64x64 Time to maturity (in years), as a 64x64 fixed point representation
     * @param isCall Whether it is for call or put
     * @return Black scholes price, as an uint256 with 18 decimals
     */
    function getBlackScholesPrice(
        address base,
        address underlying,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (uint256);
}
