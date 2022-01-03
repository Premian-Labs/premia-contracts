// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {OwnableInternal, OwnableStorage} from "@solidstate/contracts/access/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

import {OptionMath} from "../libraries/OptionMath.sol";
import {ParameterStorage} from "./ParameterStorage.sol";

/**
 * @title Premia volatility surface oracle contract
 */
contract ImpliedVolOracle is OwnableInternal {
    using ParameterStorage for ParameterStorage.Layout;
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
        ParameterStorage.Layout storage layout = ParameterStorage.layout();

        for (uint256 i = 0; i < _addr.length; i++) {
            layout.whitelisted.add(_addr[i]);
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
        ParameterStorage.Layout storage layout = ParameterStorage.layout();

        for (uint256 i = 0; i < _addr.length; i++) {
            layout.whitelisted.remove(_addr[i]);
        }
    }

    /**
     * @notice Get the list of whitelisted relayers
     * @return The list of whitelisted relayers
     */
    function getWhitelistedRelayers() external view returns (address[] memory) {
        ParameterStorage.Layout storage layout = ParameterStorage.layout();

        uint256 length = layout.whitelisted.length();
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = layout.whitelisted.at(i);
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
        returns (ParameterStorage.Update memory)
    {
        ParameterStorage.Layout storage layout = ParameterStorage.layout();
        return layout.parameters[base][underlying];
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
        ParameterStorage.Layout storage layout = ParameterStorage.layout();
        bytes32 packed = layout.getParams(base, underlying);
        return ParameterStorage.parse(packed);
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
    function getImpliedVol64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) public view returns (int128) {
        ParameterStorage.Layout storage layout = ParameterStorage.layout();

        int256[] memory params = ParameterStorage.parse(
            layout.getParams(base, underlying)
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
        int128 annualizedVol = getImpliedVol64x64(
            base,
            underlying,
            strike64x64,
            spot64x64,
            timeToMaturity64x64
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
    function update(
        address base,
        address underlying,
        bytes32 params
    ) external {
        ParameterStorage.Layout storage layout = ParameterStorage.layout();

        require(
            layout.whitelisted.contains(msg.sender),
            "Relayer not whitelisted"
        );

        layout.parameters[base][underlying] = ParameterStorage.Update({
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
    function parse(bytes32 input)
        external
        pure
        returns (int256[] memory params)
    {
        return ParameterStorage.parse(input);
    }

    /**
     * @notice Pack IV model parameters into a single bytes32
     * @dev This function is used to pack the parameters into a single variable, which is then used as input in `update`
     * @param params Parameters of IV model to pack
     * @return result The packed parameters of IV model
     */
    function format(int256[5] memory params)
        external
        pure
        returns (bytes32 result)
    {
        return ParameterStorage.format(params);
    }
}
