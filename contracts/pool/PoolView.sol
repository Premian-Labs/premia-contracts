// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {PoolStorage} from "./PoolStorage.sol";

import {IPoolView} from "./IPoolView.sol";
import {PoolInternal} from "./PoolInternal.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolView is IPoolView, PoolInternal {
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address weth,
        address feeReceiver,
        address feeDiscountAddress,
        int128 fee64x64,
        uint256 batchingPeriod
    )
        PoolInternal(
            weth,
            feeReceiver,
            feeDiscountAddress,
            fee64x64,
            batchingPeriod
        )
    {}

    /**
     * @notice get pool settings
     * @return pool settings
     */
    function getPoolSettings()
        external
        view
        returns (PoolStorage.PoolSettings memory)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return
            PoolStorage.PoolSettings(
                l.underlying,
                l.base,
                l.underlyingOracle,
                l.baseOracle
            );
    }

    /**
     * @notice get the list of all existing token ids
     * @return list of all existing token ids
     */
    function getTokenIds() external view override returns (uint256[] memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 length = l.tokenIds.length();
        uint256[] memory result = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = l.tokenIds.at(i);
        }

        return result;
    }

    /**
     * @notice get C Level
     * @return 64x64 fixed point representation of C-Level of Pool after purchase
     */
    function getCLevel64x64(bool isCall) external view returns (int128) {
        return PoolStorage.layout().getCLevel(isCall);
    }

    /**
     * @notice get ema log returns
     * @return 64x64 fixed point representation of natural log of rate of return for current period
     */
    function getEmaLogReturns64x64() external view returns (int128) {
        return PoolStorage.layout().emaLogReturns64x64;
    }

    /**
     * @notice get ema variance annualized
     * @return 64x64 fixed point representation of ema variance annualized
     */
    function getEmaVarianceAnnualized64x64() external view returns (int128) {
        return PoolStorage.layout().emaVarianceAnnualized64x64;
    }

    /**
     * @notice get price at timestamp
     * @return price at timestamp
     */
    function getPrice(uint256 timestamp) external view returns (int128) {
        return PoolStorage.layout().getPriceUpdate(timestamp);
    }

    /**
     * @notice get parameters for token id
     * @return parameters for token id
     */
    function getParametersForTokenId(uint256 tokenId)
        external
        pure
        returns (
            PoolStorage.TokenType,
            uint64,
            int128
        )
    {
        return PoolStorage.parseTokenId(tokenId);
    }
}
