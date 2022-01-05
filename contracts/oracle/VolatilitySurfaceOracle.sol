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

    event UpdateCoefficients(
        address indexed baseToken,
        address indexed underlyingToken,
        bytes32 callCoefficients, // Coefficients must be packed using formatVolatilitySurfaceCoefficients
        bytes32 putCoefficients // Coefficients must be packed using formatVolatilitySurfaceCoefficients
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
     * @notice Get the volatility surface data of a token pair
     * @param baseToken The base token of the pair
     * @param underlyingToken The underlying token of the pair
     * @return The volatility surface data
     */
    function getVolatilitySurface(address baseToken, address underlyingToken)
        external
        view
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
     * @param isCall whether it is for call or put
     * @return The unpacked coefficients of the volatility surface
     */
    function getVolatilitySurfaceCoefficientsUnpacked(
        address baseToken,
        address underlyingToken,
        bool isCall
    ) external view returns (int256[] memory) {
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
     * @param baseToken The base token of the pair
     * @param underlyingToken The underlying token of the pair
     * @param spot64x64 The spot, as a 64x64 fixed point representation
     * @param strike64x64 The strike, as a 64x64 fixed point representation
     * @param timeToMaturity64x64 Time to maturity (in years), as a 64x64 fixed point representation
     * @param isCall whether it is for call or put
     * @return Annualized volatility, as a 64x64 fixed point representation. 1 = 100%
     */
    function getAnnualizedVolatility64x64(
        address baseToken,
        address underlyingToken,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) public view returns (int128) {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();
        int256[] memory volatilitySurface = VolatilitySurfaceOracleStorage
            .parseVolatilitySurfaceCoefficients(
                l.getCoefficients(baseToken, underlyingToken, isCall)
            );

        return
            _getAnnualizedVolatility64x64(
                spot64x64,
                strike64x64,
                timeToMaturity64x64,
                volatilitySurface
            );
    }

    function _getAnnualizedVolatility64x64(
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        int256[] memory volatilitySurface
    ) internal pure returns (int128) {
        require(volatilitySurface.length == 5, "Invalid vol surface");

        // Time adjusted log moneyness
        int128 adjustedLogMoneyness64x64 = spot64x64.div(strike64x64).ln().div(
            timeToMaturity64x64.sqrt()
        );

        return
            _toCoefficient64x64(volatilitySurface[0]) +
            _toCoefficient64x64(volatilitySurface[1]).mul(
                adjustedLogMoneyness64x64
            ) +
            _toCoefficient64x64(volatilitySurface[2]).mul(
                adjustedLogMoneyness64x64.mul(adjustedLogMoneyness64x64)
            ) +
            _toCoefficient64x64(volatilitySurface[3]).mul(timeToMaturity64x64) +
            _toCoefficient64x64(volatilitySurface[4])
                .mul(adjustedLogMoneyness64x64)
                .mul(timeToMaturity64x64);
    }

    function _toCoefficient64x64(int256 value) internal pure returns (int128) {
        return ABDKMath64x64.divi(value, int256(10**DECIMALS));
    }

    function _getBlackScholesPrice64x64(
        address baseToken,
        address underlyingToken,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) internal view returns (int128) {
        int128 annualizedVolatility = getAnnualizedVolatility64x64(
            baseToken,
            underlyingToken,
            strike64x64,
            spot64x64,
            timeToMaturity64x64,
            isCall
        );
        int128 annualizedVariance = annualizedVolatility.mul(
            annualizedVolatility
        );

        return
            OptionMath._blackScholesPrice(
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
    ) external view returns (int128) {
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
    ) external view returns (uint256) {
        return
            _getBlackScholesPrice64x64(
                baseToken,
                underlyingToken,
                strike64x64,
                spot64x64,
                timeToMaturity64x64,
                isCall
            ).mulu(10**18);
    }

    /**
     * @notice Update a list of volatility surfaces
     * @param baseTokens List of base tokens
     * @param underlyingTokens List of underlying tokens
     * @param callCoefficients List of call coefficients
     * @param putCoefficients List of put coefficients
     */
    function updateVolatilitySurfaces(
        address[] memory baseTokens,
        address[] memory underlyingTokens,
        bytes32[] memory callCoefficients,
        bytes32[] memory putCoefficients
    ) external {
        uint256 length = baseTokens.length;
        require(
            length == underlyingTokens.length &&
                length == callCoefficients.length &&
                length == putCoefficients.length,
            "Wrong array length"
        );

        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        require(
            l.whitelistedRelayers.contains(msg.sender),
            "Relayer not whitelisted"
        );

        for (uint256 i = 0; i < length; i++) {
            l.volatilitySurfaces[baseTokens[i]][
                    underlyingTokens[i]
                ] = VolatilitySurfaceOracleStorage.Update({
                updatedAt: block.timestamp,
                callCoefficients: callCoefficients[i],
                putCoefficients: putCoefficients[i]
            });

            emit UpdateCoefficients(
                baseTokens[i],
                underlyingTokens[i],
                callCoefficients[i],
                putCoefficients[i]
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
     * @dev This function is used to pack the coefficients into a single variable, which is then used as input in `updateVolatilitySurfaces`
     * @param coefficients Coefficients of the volatility surface to pack
     * @return result The packed coefficients of the volatility surface
     */
    function formatVolatilitySurfaceCoefficients(int256[5] memory coefficients)
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
