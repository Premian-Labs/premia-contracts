// SPDX-License-Identifier: UNLICENSED

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

    uint256 internal constant COEFFICIENT_DECIMALS = 3;

    struct VolatilitySurfaceInputParams {
        address baseToken;
        address underlyingToken;
        bytes32 callCoefficients;
        bytes32 putCoefficients;
    }

    event UpdateCoefficients(
        address indexed baseToken,
        address indexed underlyingToken,
        bytes32 callCoefficients,
        bytes32 putCoefficients
    );

    /// @notice Add relayer to the whitelist so that they can add oracle surfaces.
    /// @param _addr The addresses to add to the whitelist
    function addWhitelistedRelayer(address[] memory _addr) external onlyOwner {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        for (uint256 i = 0; i < _addr.length; i++) {
            l.whitelistedRelayers.add(_addr[i]);
        }
    }

    /// @notice Remove relayer from the whitelist so that they cannot add oracle surfaces.
    /// @param _addr The addresses to remove the whitelist
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

    /// @notice Get the list of whitelisted relayers
    /// @return The list of whitelisted relayers
    function getWhitelistedRelayers()
        external
        view
        override
        returns (address[] memory)
    {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        uint256 length = l.whitelistedRelayers.length();
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = l.whitelistedRelayers.at(i);
        }

        return result;
    }

    function getVolatilitySurfacePacked(
        address baseToken,
        address underlyingToken,
        bool isCall
    ) external view override returns (bytes32) {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();
        return l.volatilitySurfaces[baseToken][underlyingToken][isCall];
    }

    function getVolatilitySurfaceUnpacked(
        address baseToken,
        address underlyingToken,
        bool isCall
    ) external view override returns (int256[] memory) {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();
        return
            VolatilitySurfaceOracleStorage.parseVolatilitySurfaceCoefficients(
                l.volatilitySurfaces[baseToken][underlyingToken][isCall]
            );
    }

    function getLastUpdateTimestamp(address baseToken, address underlyingToken)
        external
        view
        override
        returns (uint256)
    {
        return
            VolatilitySurfaceOracleStorage.layout().lastUpdateTimestamps[
                baseToken
            ][underlyingToken];
    }

    function getTimeToMaturity64x64(uint64 maturity)
        external
        view
        override
        returns (int128)
    {
        return ABDKMath64x64.divu(maturity - block.timestamp, 365 days);
    }

    function getAnnualizedVolatility64x64(
        address baseToken,
        address underlyingToken,
        int128 strikeToSpotRatio64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) public view override returns (int128) {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();
        int256[] memory volatilitySurface = VolatilitySurfaceOracleStorage
            .parseVolatilitySurfaceCoefficients(
                l.volatilitySurfaces[baseToken][underlyingToken][isCall]
            );

        return
            _getAnnualizedVolatility64x64(
                strikeToSpotRatio64x64,
                timeToMaturity64x64,
                volatilitySurface
            );
    }

    function _getAnnualizedVolatility64x64(
        int128 strikeToSpotRatio64x64,
        int128 timeToMaturity64x64,
        int256[] memory volatilitySurface
    ) internal pure returns (int128) {
        require(volatilitySurface.length == 10, "Invalid vol surface");

        int128 maturitySquared64x64 = timeToMaturity64x64.mul(
            timeToMaturity64x64
        );
        int128 strikeToSpotSquared64x64 = strikeToSpotRatio64x64.mul(
            strikeToSpotRatio64x64
        );

        //c_0 (hist_vol) + c_1 * maturity + c_2 * maturity^2
        return
            _getCoefficient64x64(volatilitySurface[0]) +
            _getCoefficient64x64(volatilitySurface[1]).mul(
                timeToMaturity64x64
            ) +
            _getCoefficient64x64(volatilitySurface[2]).mul(
                maturitySquared64x64
            ) +
            //+ c_3 * maturity^3 + c_4 * strikeToSpot
            _getCoefficient64x64(volatilitySurface[3]).mul(
                maturitySquared64x64.mul(timeToMaturity64x64)
            ) +
            _getCoefficient64x64(volatilitySurface[4]).mul(
                strikeToSpotRatio64x64
            ) +
            //+ c_5 * strikeToSpot^2 + c_6 * strikeToSpot^3
            _getCoefficient64x64(volatilitySurface[5]).mul(
                strikeToSpotSquared64x64
            ) +
            _getCoefficient64x64(volatilitySurface[6]).mul(
                strikeToSpotSquared64x64.mul(strikeToSpotRatio64x64)
            ) +
            //+ c_7 * maturity * strikeToSpot
            _getCoefficient64x64(volatilitySurface[7]).mul(
                timeToMaturity64x64.mul(strikeToSpotRatio64x64)
            ) +
            //+ c_8 * strikeToSpot^2 * maturity
            _getCoefficient64x64(volatilitySurface[8]).mul(
                strikeToSpotSquared64x64.mul(timeToMaturity64x64)
            ) +
            //+ c_9 * maturity^2 * strikeToSpot
            _getCoefficient64x64(volatilitySurface[9]).mul(
                maturitySquared64x64.mul(strikeToSpotRatio64x64)
            );
    }

    function _getCoefficient64x64(int256 value) internal pure returns (int128) {
        return ABDKMath64x64.divi(value, int256(10**COEFFICIENT_DECIMALS));
    }

    function _getBlackScholesPrice64x64(
        address baseToken,
        address underlyingToken,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) internal view returns (int128) {
        int128 strikeToSpotRatio = strike64x64.div(spot64x64);
        int128 annualizedVolatility = getAnnualizedVolatility64x64(
            baseToken,
            underlyingToken,
            strikeToSpotRatio,
            timeToMaturity64x64,
            isCall
        );
        int128 annualizedVariance = annualizedVolatility.mul(
            annualizedVolatility
        );

        return
            OptionMath._bsPrice(
                annualizedVariance,
                strike64x64,
                spot64x64,
                timeToMaturity64x64,
                isCall
            );
    }

    function getBlackScholesPrice64x64(
        address baseToken,
        address underlyingToken,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view override returns (int128) {
        return
            _getBlackScholesPrice64x64(
                baseToken,
                underlyingToken,
                strike64x64,
                spot64x64,
                timeToMaturity64x64,
                isCall
            );
    }

    function getBlackScholesPrice(
        address baseToken,
        address underlyingToken,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view override returns (uint256) {
        return
            ABDKMath64x64.toUInt(
                _getBlackScholesPrice64x64(
                    baseToken,
                    underlyingToken,
                    strike64x64,
                    spot64x64,
                    timeToMaturity64x64,
                    isCall
                )
            );
    }

    function updateVolatilitySurfaces(
        VolatilitySurfaceInputParams[] memory surfaces
    ) external {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        require(
            l.whitelistedRelayers.contains(msg.sender),
            "Relayer not whitelisted"
        );

        for (uint256 i = 0; i < surfaces.length; i++) {
            VolatilitySurfaceInputParams memory surfaceParams = surfaces[i];

            l.volatilitySurfaces[surfaceParams.baseToken][
                surfaceParams.underlyingToken
            ][true] = surfaceParams.callCoefficients;

            l.volatilitySurfaces[surfaceParams.baseToken][
                surfaceParams.underlyingToken
            ][false] = surfaceParams.putCoefficients;

            l.lastUpdateTimestamps[surfaceParams.baseToken][
                surfaceParams.underlyingToken
            ] = block.timestamp;

            emit UpdateCoefficients(
                surfaceParams.baseToken,
                surfaceParams.underlyingToken,
                surfaceParams.callCoefficients,
                surfaceParams.putCoefficients
            );
        }
    }

    function parseVolatilitySurfaceCoefficients(bytes32 input)
        external
        view
        returns (int256[] memory coefficients)
    {
        return
            VolatilitySurfaceOracleStorage.parseVolatilitySurfaceCoefficients(
                input
            );
    }

    function formatVolatilitySurfaceCoefficients(int256[10] memory coefficients)
        external
        view
        returns (bytes32 result)
    {
        return
            VolatilitySurfaceOracleStorage.formatVolatilitySurfaceCoefficients(
                coefficients
            );
    }
}
