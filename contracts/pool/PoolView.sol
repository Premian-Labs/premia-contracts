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
        address poolMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 fee64x64
    )
        PoolInternal(
            weth,
            poolMining,
            feeReceiver,
            feeDiscountAddress,
            fee64x64
        )
    {}

    /**
     * @notice get pool settings
     * @return pool settings
     */
    function getPoolSettings()
        external
        view
        override
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
    function getCLevel64x64(bool isCall)
        external
        view
        override
        returns (int128)
    {
        return PoolStorage.layout().getCLevel(isCall);
    }

    /**
     * @notice get ema log returns
     * @return 64x64 fixed point representation of natural log of rate of return for current period
     */
    function getEmaLogReturns64x64() external view override returns (int128) {
        return PoolStorage.layout().emaLogReturns64x64;
    }

    /**
     * @notice get ema variance annualized
     * @return 64x64 fixed point representation of ema variance annualized
     */
    function getEmaVarianceAnnualized64x64()
        external
        view
        override
        returns (int128)
    {
        return PoolStorage.layout().emaVarianceAnnualized64x64;
    }

    /**
     * @notice get price at timestamp
     * @return price at timestamp
     */
    function getPrice(uint256 timestamp)
        external
        view
        override
        returns (int128)
    {
        return PoolStorage.layout().getPriceUpdate(timestamp);
    }

    /**
     * @notice get parameters for token id
     * @return parameters for token id
     */
    function getParametersForTokenId(uint256 tokenId)
        external
        pure
        override
        returns (
            PoolStorage.TokenType,
            uint64,
            int128
        )
    {
        return PoolStorage.parseTokenId(tokenId);
    }

    /**
     * @notice get minimum purchase and interval amounts
     * @return minCallTokenAmount minimum call pool amount
     * @return minPutTokenAmount minimum put pool amount
     */
    function getMinimumAmounts()
        external
        view
        override
        returns (uint256 minCallTokenAmount, uint256 minPutTokenAmount)
    {
        return (_getMinimumAmount(true), _getMinimumAmount(false));
    }

    /**
     * @notice get user total value locked
     * @return underlyingTVL user total value locked in call pool (in underlying token amount)
     * @return baseTVL user total value locked in put pool (in base token amount)
     */
    function getUserTVL(address user)
        external
        view
        override
        returns (uint256 underlyingTVL, uint256 baseTVL)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (l.userTVL[user][true], l.userTVL[user][false]);
    }

    /**
     * @notice get total value locked
     * @return underlyingTVL total value locked in call pool (in underlying token amount)
     * @return baseTVL total value locked in put pool (in base token amount)
     */
    function getTotalTVL()
        external
        view
        override
        returns (uint256 underlyingTVL, uint256 baseTVL)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (l.totalTVL[true], l.totalTVL[false]);
    }

    /**
     * @notice get the addres of PoolMining contract
     * @return address of PoolMining contract
     */
    function getPoolMining() external view override returns (address) {
        return POOL_MINING_ADDRESS;
    }
}
