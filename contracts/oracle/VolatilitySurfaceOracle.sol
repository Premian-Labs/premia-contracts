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
     * @inheritdoc IVolatilitySurfaceOracle
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
     * @inheritdoc IVolatilitySurfaceOracle
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
     * @inheritdoc IVolatilitySurfaceOracle
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
     * @inheritdoc IVolatilitySurfaceOracle
     */
    function getTimeToMaturity64x64(uint64 maturity)
        external
        view
        returns (int128)
    {
        return ABDKMath64x64.divu(maturity - block.timestamp, 365 days);
    }

    function _getAnnualizedVolatility64x64(
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        int256[] memory params
    ) internal pure returns (int128) {
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

    /**
     * @inheritdoc IVolatilitySurfaceOracle
     */
    function getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) public view returns (int128) {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        int256[] memory params = VolatilitySurfaceOracleStorage.parseParams(
            l.getParams(base, underlying)
        );

        return
            _getAnnualizedVolatility64x64(
                spot64x64,
                strike64x64,
                timeToMaturity64x64,
                params
            );
    }

    /**
     * @notice see getAnnualizedVolatility64x64(address,address,int128,int128,int128)
     * @dev deprecated - will be removed once PoolInternal call is updated
     */
    function getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        bool
    ) public view returns (int128) {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        int256[] memory params = VolatilitySurfaceOracleStorage.parseParams(
            l.getParams(base, underlying)
        );

        return
            _getAnnualizedVolatility64x64(
                spot64x64,
                strike64x64,
                timeToMaturity64x64,
                params
            );
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
     * @inheritdoc IVolatilitySurfaceOracle
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
     * @inheritdoc IVolatilitySurfaceOracle
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
     * @notice Update a list of IV model parameters
     * @param base List of base tokens
     * @param underlying List of underlying tokens
     * @param parameters List of IV model parameters
     */
    function updateParams(
        address[] memory base,
        address[] memory underlying,
        bytes32[] memory parameters
    ) external {
        uint256 length = base.length;
        require(
            length == underlying.length && length == parameters.length,
            "Wrong array length"
        );

        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        require(
            l.whitelistedRelayers.contains(msg.sender),
            "Relayer not whitelisted"
        );

        for (uint256 i = 0; i < length; i++) {
            l.parameters[base[i]][
                underlying[i]
            ] = VolatilitySurfaceOracleStorage.Update({
                updatedAt: block.timestamp,
                params: parameters[i]
            });

            emit UpdateParameters(base[i], underlying[i], parameters[i]);
        }
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
