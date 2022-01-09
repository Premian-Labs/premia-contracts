// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {VolatilitySurfaceOracleStorage} from "./VolatilitySurfaceOracleStorage.sol";

interface IVolatilitySurfaceOracle {
    /**
     * @notice Pack IV model parameters into a single bytes32
     * @dev This function is used to pack the parameters into a single variable, which is then used as input in `update`
     * @param params Parameters of IV model to pack
     * @return result The packed parameters of IV model
     */
    function formatParams(int256[5] memory params)
        external
        pure
        returns (bytes32 result);

    /**
     * @notice Unpack IV model parameters from a bytes32
     * @param input Packed IV model parameters to unpack
     * @return params The unpacked parameters of the IV model
     */
    function parseParams(bytes32 input)
        external
        pure
        returns (int256[] memory params);

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
     * @notice calculate the annualized volatility for given set of parameters
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param spot64x64 64x64 fixed point representation of spot price
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param timeToMaturity64x64 64x64 fixed point representation of time to maturity (denominated in years)
     * @return 64x64 fixed point representation of annualized implied volatility, where 1 is defined as 100%
     */
    function getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) external view returns (int128);

    /**
     * @notice calculate the price of an option using the Black-Scholes model
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param strike64x64 Strike, as a64x64 fixed point representation
     * @param spot64x64 Spot price, as a 64x64 fixed point representation
     * @param timeToMaturity64x64 64x64 fixed point representation of time to maturity (denominated in years)
     * @param isCall Whether it is for call or put
     * @return 64x64 fixed point representation of the Black Scholes price
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
     * @param timeToMaturity64x64 64x64 fixed point representation of time to maturity (denominated in years)
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

    /**
     * @notice Add relayers to the whitelist so that they can add oracle surfaces
     * @param accounts The addresses to add to the whitelist
     */
    function addWhitelistedRelayers(address[] memory accounts) external;

    /**
     * @notice Remove relayers from the whitelist so that they cannot add oracle surfaces
     * @param accounts The addresses to remove from the whitelist
     */
    function removeWhitelistedRelayers(address[] memory accounts) external;

    /**
     * @notice Update a list of IV model parameters
     * @param base List of base tokens
     * @param underlying List of underlying tokens
     * @param parameters List of IV model parameters
     */
    function updateParams(
        address[] memory base,
        address[] memory underlying,
        bytes32[] memory parameters
    ) external;
}
