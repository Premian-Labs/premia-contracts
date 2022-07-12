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

    uint256 private constant DECIMALS = 12;

    int128 private constant MIN_TIME_TO_MATURITY_64x64 = 0x21aa6ed1021aa6f; // 3d (3/365)
    int128 private constant MIN_MONEYNESS_64x64 = 0x8000000000000000; // 0.5
    int128 private constant MAX_MONEYNESS_64x64 = 0x20000000000000000; // 2.0

    event UpdateParameters(
        address indexed base,
        address indexed underlying,
        bytes32 params // Parameters for volatility model
    );

    /**
     * @inheritdoc IVolatilitySurfaceOracle
     */
    function formatParams(int256[5] memory params)
        external
        pure
        returns (bytes32 result)
    {
        return VolatilitySurfaceOracleStorage.formatParams(params);
    }

    /**
     * @inheritdoc IVolatilitySurfaceOracle
     */
    function parseParams(bytes32 input)
        external
        pure
        returns (int256[] memory params)
    {
        return VolatilitySurfaceOracleStorage.parseParams(input);
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

    /**
     * @inheritdoc IVolatilitySurfaceOracle
     */
    function getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) external view returns (int128) {
        return
            _getAnnualizedVolatility64x64(
                base,
                underlying,
                spot64x64,
                strike64x64,
                timeToMaturity64x64
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
    ) external view returns (int128) {
        return
            _getAnnualizedVolatility64x64(
                base,
                underlying,
                spot64x64,
                strike64x64,
                timeToMaturity64x64
            );
    }

    /**
     * @inheritdoc IVolatilitySurfaceOracle
     */
    function getBlackScholesPrice64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (int128) {
        return
            _getBlackScholesPrice64x64(
                base,
                underlying,
                spot64x64,
                strike64x64,
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
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (uint256) {
        return
            _getBlackScholesPrice64x64(
                base,
                underlying,
                spot64x64,
                strike64x64,
                timeToMaturity64x64,
                isCall
            ).mulu(10**18);
    }

    /**
     * @inheritdoc IVolatilitySurfaceOracle
     */
    function addWhitelistedRelayers(address[] memory accounts)
        external
        onlyOwner
    {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            l.whitelistedRelayers.add(accounts[i]);
        }
    }

    /**
     * @inheritdoc IVolatilitySurfaceOracle
     */
    function removeWhitelistedRelayers(address[] memory accounts)
        external
        onlyOwner
    {
        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            l.whitelistedRelayers.remove(accounts[i]);
        }
    }

    /**
     * @inheritdoc IVolatilitySurfaceOracle
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
     * @notice convert decimal parameter to 64x64 fixed point representation
     * @param value parameter to convert
     * @return 64x64 fixed point representation of parameter
     */
    function _toParameter64x64(int256 value) private pure returns (int128) {
        return ABDKMath64x64.divi(value, int256(10**DECIMALS));
    }

    /**
     * @notice calculate the annualized volatility for given set of parameters
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param spot64x64 64x64 fixed point representation of spot price
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param timeToMaturity64x64 64x64 fixed point representation of time to maturity (denominated in years)
     * @return 64x64 fixed point representation of annualized implied volatility, where 1 is defined as 100%
     */
    function _getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) private view returns (int128) {
        if (timeToMaturity64x64 < MIN_TIME_TO_MATURITY_64x64) {
            timeToMaturity64x64 = MIN_TIME_TO_MATURITY_64x64;
        }

        VolatilitySurfaceOracleStorage.Layout
            storage l = VolatilitySurfaceOracleStorage.layout();

        int256[] memory params = VolatilitySurfaceOracleStorage.parseParams(
            l.getParams(base, underlying)
        );

        int128 moneyness64x64 = spot64x64.div(strike64x64);

        if (moneyness64x64 < MIN_MONEYNESS_64x64) {
            moneyness64x64 = MIN_MONEYNESS_64x64;
        } else if (moneyness64x64 > MAX_MONEYNESS_64x64) {
            moneyness64x64 = MAX_MONEYNESS_64x64;
        }

        // Time adjusted log moneyness
        int128 M64x64 = moneyness64x64.ln().div(timeToMaturity64x64.sqrt());

        return
            _toParameter64x64(params[0]) +
            _toParameter64x64(params[1]).mul(M64x64) +
            _toParameter64x64(params[2]).mul(M64x64.mul(M64x64)) +
            _toParameter64x64(params[3]).mul(timeToMaturity64x64) +
            _toParameter64x64(params[4]).mul(M64x64).mul(timeToMaturity64x64);
    }

    /**
     * @notice calculate the price of an option using the Black-Scholes model
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param spot64x64 Spot price, as a 64x64 fixed point representation
     * @param strike64x64 Strike, as a64x64 fixed point representation
     * @param timeToMaturity64x64 64x64 fixed point representation of time to maturity (denominated in years)
     * @param isCall Whether it is for call or put
     * @return 64x64 fixed point representation of the Black Scholes price
     */
    function _getBlackScholesPrice64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) private view returns (int128) {
        int128 annualizedVol = _getAnnualizedVolatility64x64(
            base,
            underlying,
            spot64x64,
            strike64x64,
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
}
