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

    uint256 internal constant C0_DECIMALS = 4;
    uint256 internal constant C1_DECIMALS = 5;
    uint256 internal constant C2_DECIMALS = 7;
    uint256 internal constant C3_DECIMALS = 8;
    uint256 internal constant C4_DECIMALS = 3;
    uint256 internal constant C5_DECIMALS = 5;
    uint256 internal constant C6_DECIMALS = 4;
    uint256 internal constant C7_DECIMALS = 4;
    uint256 internal constant C8_DECIMALS = 7;
    uint256 internal constant C9_DECIMALS = 6;

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

    /**
     * @notice Get the volatility surface data of a token pair
     * @param baseToken The base token of the pair
     * @param underlyingToken The underlying token of the pair
     * @return The volatility surface data
     */
    function getVolatilitySurface(address baseToken, address underlyingToken)
        external
        view
        override
        returns (VolatilitySurfaceOracleStorage.Update memory)
    {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();
        return l.volatilitySurfaces[baseToken][underlyingToken];
    }

    /**
     * @notice Get unpacked volatility surface coefficients
     * @param baseToken The base token of the pair
     * @param underlyingToken The underlying token of the pair
     * @param isCall Whether it is for call or put
     * @return The unpacked coefficients of the volatility surface
     */
    function getVolatilitySurfaceCoefficientsUnpacked(
        address baseToken,
        address underlyingToken,
        bool isCall
    ) external view override returns (int256[] memory) {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        bytes32 valuePacked = l.getCoefficients(
            baseToken,
            underlyingToken,
            isCall
        );

        return
            VolatilitySurfaceOracleStorage.parseVolatilitySurfaceCoefficients(
                valuePacked
            );
    }

    /**
     * @notice Get amount of decimals for each coefficient
     * @return result Amount of decimals to use for each coefficient
     */
    function getCoefficientsDecimals()
        external
        pure
        returns (uint256[] memory result)
    {
        result = new uint256[](10);
        result[0] = C0_DECIMALS;
        result[1] = C1_DECIMALS;
        result[2] = C2_DECIMALS;
        result[3] = C3_DECIMALS;
        result[4] = C4_DECIMALS;
        result[5] = C5_DECIMALS;
        result[6] = C6_DECIMALS;
        result[7] = C7_DECIMALS;
        result[8] = C8_DECIMALS;
        result[9] = C9_DECIMALS;
    }

    /**
     * @notice Get time to maturity in years, as a 64x64 fixed point representation
     * @param maturity Maturity timestamp
     * @return Time to maturity (in years), as a 64x64 fixed point representation
     */
    function getTimeToMaturity64x64(uint64 maturity)
        external
        view
        override
        returns (int128)
    {
        return ABDKMath64x64.divu(maturity - block.timestamp, 365 days);
    }

    /**
     * @notice Get annualized volatility as a 64x64 fixed point representation
     * @param baseToken The base token of the pair
     * @param underlyingToken The underlying token of the pair
     * @param strikeToSpotRatio64x64 Strike to spot ratio, as a 64x64 fixed point representation
     * @param timeToMaturity64x64 Time to maturity (in years), as a 64x64 fixed point representation
     * @param isCall Whether it is for call or put
     * @return Annualized volatility, as a 64x64 fixed point representation. 1 = 100%
     */
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
                l.getCoefficients(baseToken, underlyingToken, isCall)
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
            (_toCoefficient64x64(volatilitySurface[0], C0_DECIMALS) +
                _toCoefficient64x64(volatilitySurface[1], C1_DECIMALS).mul(
                    timeToMaturity64x64
                ) +
                _toCoefficient64x64(volatilitySurface[2], C2_DECIMALS).mul(
                    maturitySquared64x64
                ) +
                //+ c_3 * maturity^3 + c_4 * strikeToSpot
                _toCoefficient64x64(volatilitySurface[3], C3_DECIMALS).mul(
                    maturitySquared64x64.mul(timeToMaturity64x64)
                ) +
                _toCoefficient64x64(volatilitySurface[4], C4_DECIMALS).mul(
                    strikeToSpotRatio64x64
                ) +
                //+ c_5 * strikeToSpot^2 + c_6 * strikeToSpot^3
                _toCoefficient64x64(volatilitySurface[5], C5_DECIMALS).mul(
                    strikeToSpotSquared64x64
                ) +
                _toCoefficient64x64(volatilitySurface[6], C6_DECIMALS).mul(
                    strikeToSpotSquared64x64.mul(strikeToSpotRatio64x64)
                ) +
                //+ c_7 * maturity * strikeToSpot
                _toCoefficient64x64(volatilitySurface[7], C7_DECIMALS).mul(
                    timeToMaturity64x64.mul(strikeToSpotRatio64x64)
                ) +
                //+ c_8 * strikeToSpot^2 * maturity
                _toCoefficient64x64(volatilitySurface[8], C8_DECIMALS).mul(
                    strikeToSpotSquared64x64.mul(timeToMaturity64x64)
                ) +
                //+ c_9 * maturity^2 * strikeToSpot
                _toCoefficient64x64(volatilitySurface[9], C9_DECIMALS).mul(
                    maturitySquared64x64.mul(strikeToSpotRatio64x64)
                )).div(0x640000000000000000); // Divide by 100, so that value of 1 = 100% volatility
    }

    function _toCoefficient64x64(int256 value, uint256 decimals)
        internal
        pure
        returns (int128)
    {
        return ABDKMath64x64.divi(value, int256(10**decimals));
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

    /**
     * @notice Get Black Scholes price as a 64x64 fixed point representation
     * @param baseToken The base token of the pair
     * @param underlyingToken The underlying token of the pair
     * @param strike64x64 Strike, as a64x64 fixed point representation
     * @param spot64x64 Spot price, as a 64x64 fixed point representation
     * @param timeToMaturity64x64 Time to maturity (in years), as a 64x64 fixed point representation
     * @param isCall Whether it is for call or put
     * @return Black scholes price, as a 64x64 fixed point representation
     */
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

    /**
     * @notice Get Black Scholes price as an uint256 with 18 decimals
     * @param baseToken The base token of the pair
     * @param underlyingToken The underlying token of the pair
     * @param strike64x64 Strike, as a64x64 fixed point representation
     * @param spot64x64 Spot price, as a 64x64 fixed point representation
     * @param timeToMaturity64x64 Time to maturity (in years), as a 64x64 fixed point representation
     * @param isCall Whether it is for call or put
     * @return Black scholes price, as an uint256 with 18 decimals
     */
    function getBlackScholesPrice(
        address baseToken,
        address underlyingToken,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view override returns (uint256) {
        return
            ABDKMath64x64.mulu(
                _getBlackScholesPrice64x64(
                    baseToken,
                    underlyingToken,
                    strike64x64,
                    spot64x64,
                    timeToMaturity64x64,
                    isCall
                ),
                10**18
            );
    }

    /**
     * @notice Update a list of volatility surfaces
     * @param surfaces List of volatility surfaces to update
     */
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
                ] = VolatilitySurfaceOracleStorage.Update({
                updatedAt: block.timestamp,
                callCoefficients: surfaceParams.callCoefficients,
                putCoefficients: surfaceParams.putCoefficients
            });

            emit UpdateCoefficients(
                surfaceParams.baseToken,
                surfaceParams.underlyingToken,
                surfaceParams.callCoefficients,
                surfaceParams.putCoefficients
            );
        }
    }

    /**
     * @notice Unpack volatility surface coefficients from a bytes43
     * @param input Packed volatility surface coefficients to unpack
     * @return coefficients The unpacked coefficients of the volatility surface
     */
    function parseVolatilitySurfaceCoefficients(bytes32 input)
        external
        pure
        returns (int256[] memory coefficients)
    {
        return
            VolatilitySurfaceOracleStorage.parseVolatilitySurfaceCoefficients(
                input
            );
    }

    /**
     * @notice Pack volatility surface coefficients into a single bytes32
     * @param coefficients Coefficients of the volatility surface to pack
     * @return result The packed coefficients of the volatility surface
     */
    function formatVolatilitySurfaceCoefficients(int256[10] memory coefficients)
        external
        pure
        returns (bytes32 result)
    {
        return
            VolatilitySurfaceOracleStorage.formatVolatilitySurfaceCoefficients(
                coefficients
            );
    }
}
