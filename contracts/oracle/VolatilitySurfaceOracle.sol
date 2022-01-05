// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {OwnableInternal, OwnableStorage} from "@solidstate/contracts/access/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

import {OptionMath} from "../libraries/OptionMath.sol";
import {VolatilitySurfaceOracleStorage} from "./VolatilitySurfaceOracleStorage.sol";
import {IVolatilitySurfaceOracle} from "./IVolatilitySurfaceOracle.sol";

/**
 * @title Premia volatility surface oracle contract
 */
contract VolatilitySurfaceOracle is IVolatilitySurfaceOracle, OwnableInternal {
    using VolatilitySurfaceOracleStorage for VolatilitySurfaceOracleStorage.Layout;
    using EnumerableSet for EnumerableSet.AddressSet;
    using ABDKMath64x64 for int128;

    uint256 internal constant DECIMALS = 12;

    event UpdateParameters(
        address indexed base,
        address indexed underlying,
        bytes32 params // Parameters for volatility model
    );

    /**
     * @notice Add relayer to the whitelist so that they can add oracle surfaces.
     * @param _addr The addresses to add to the whitelist
     */
    function addWhitelistedRelayer(address[] memory _addr) external onlyOwner {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        for (uint256 i = 0; i < _addr.length; i++) {
            l.whitelistedRelayers.add(_addr[i]);
        }
    }

    /**
     * @notice Remove relayer from the whitelist so that they cannot add oracle surfaces.
     * @param _addr The addresses to remove the whitelist
     */
    function removeWhitelistedRelayer(address[] memory _addr)
        external
        onlyOwner
    {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        for (uint256 i = 0; i < _addr.length; i++) {
            l.whitelistedRelayers.remove(_addr[i]);
        }
    }

    /**
     * @notice Get the list of whitelisted relayers
     * @return The list of whitelisted relayers
     */
    function getWhitelistedRelayers() external view returns (address[] memory) {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        uint256 length = l.whitelistedRelayers.length();
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = l.whitelistedRelayers.at(i);
        }

        return result;
    }

    /**
     * @notice Get the IV model parameters of a token pair
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @return The IV model parameters
     */
    function getParams(address base, address underlying)
        external
        view
        returns (VolatilitySurfaceOracleStorage.Update memory)
    {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();
        return l.parameters[base][underlying];
    }

    /**
     * @notice Get unpacked IV model parameters
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @return The unpacked IV model parameters
     */
    function getParamsUnpacked(address base, address underlying)
        external
        view
        returns (int256[] memory)
    {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();
        bytes32 packed = l.getParams(base, underlying);
        return VolatilitySurfaceOracleStorage.parseParams(packed);
    }

    /**
     * @notice Get time to maturity in years, as a 64x64 fixed point representation
     * @param maturity Maturity timestamp
     * @return Time to maturity (in years), as a 64x64 fixed point representation
     */
    function getTimeToMaturity64x64(uint64 maturity)
        external
        view
        returns (int128)
    {
        return ABDKMath64x64.divu(maturity - block.timestamp, 365 days);
    }

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
        int128 timeToMaturity64x64,
        bool isCall
    ) public view returns (int128) {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        int256[] memory params = VolatilitySurfaceOracleStorage.parseParams(
            l.getParams(base, underlying)
        );

        require(params.length == 5, "Invalid vol surface");

        // Time adjusted log moneyness
        int128 M64x64 = spot64x64.div(strike64x64).ln().div(
            timeToMaturity64x64.sqrt()
        );

        return
            _toParameter64x64(params[0]) +
            _toParameter64x64(params[1]).mul(M64x64) +
            _toParameter64x64(params[2]).mul(M64x64.mul(M64x64)) +
            _toParameter64x64(params[3]).mul(timeToMaturity64x64) +
            _toParameter64x64(params[4]).mul(M64x64).mul(timeToMaturity64x64);
    }

    function _toParameter64x64(int256 value) internal pure returns (int128) {
        return ABDKMath64x64.divi(value, int256(10**DECIMALS));
    }

    function _getBlackScholesPrice64x64(
        address base,
        address underlying,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) internal view returns (int128) {
        int128 annualizedVol = getAnnualizedVolatility64x64(
            base,
            underlying,
            strike64x64,
            spot64x64,
            timeToMaturity64x64,
            isCall
        );
        int128 annualizedVar = annualizedVol.mul(annualizedVol);

        return
            OptionMath._blackScholesPrice(
                annualizedVar,
                strike64x64,
                spot64x64,
                timeToMaturity64x64,
                isCall
            );
    }

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
    ) external view returns (int128) {
        return
            _getBlackScholesPrice64x64(
                base,
                underlying,
                strike64x64,
                spot64x64,
                timeToMaturity64x64,
                isCall
            );
    }

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
    ) external view returns (uint256) {
        return
            _getBlackScholesPrice64x64(
                base,
                underlying,
                strike64x64,
                spot64x64,
                timeToMaturity64x64,
                isCall
            ).mulu(10**18);
    }

    /**
     * @notice Update the IV model parameters of a token pair
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param params The parameters of the IV model to be updated.
     */
    function updateParams(
        address base,
        address underlying,
        bytes32 params
    ) external {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        require(
            l.whitelistedRelayers.contains(msg.sender),
            "Relayer not whitelisted"
        );

        l.parameters[base][underlying] = VolatilitySurfaceOracleStorage.Update({
            updatedAt: block.timestamp,
            params: params
        });
        emit UpdateParameters(base, underlying, params);
    }

    /**
     * @notice Unpack IV model parameters from a bytes32
     * @param input Packed IV model parameters to unpack
     * @return params The unpacked parameters of the IV model
     */
    function parseParams(bytes32 input)
        external
        pure
        returns (int256[] memory params)
    {
        return VolatilitySurfaceOracleStorage.parseParams(input);
    }

    /**
     * @notice Pack IV model parameters into a single bytes32
     * @dev This function is used to pack the parameters into a single variable, which is then used as input in `update`
     * @param params Parameters of IV model to pack
     * @return result The packed parameters of IV model
     */
    function formatParams(int256[5] memory params)
        external
        pure
        returns (bytes32 result)
    {
        return VolatilitySurfaceOracleStorage.formatParams(params);
    }
}
