// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";

import {IPremiaOptionNFTDisplay} from "../interface/IPremiaOptionNFTDisplay.sol";
import {IPoolView, IERC1155Metadata} from "./IPoolView.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {PoolStorage} from "./PoolStorage.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolView is IPoolView, PoolInternal {
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolStorage for PoolStorage.Layout;

    address internal immutable NFT_DISPLAY_ADDRESS;

    constructor(
        address nftDisplay,
        address ivolOracle,
        address weth,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 fee64x64
    )
        PoolInternal(
            ivolOracle,
            weth,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            fee64x64
        )
    {
        NFT_DISPLAY_ADDRESS = nftDisplay;
    }

    /**
     * @inheritdoc IPoolView
     */
    function getFeeReceiverAddress() external view override returns (address) {
        return FEE_RECEIVER_ADDRESS;
    }

    /**
     * @inheritdoc IPoolView
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
     * @inheritdoc IPoolView
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
     * @inheritdoc IPoolView
     */
    function getCLevel64x64(bool isCall)
        external
        view
        override
        returns (int128 cLevel64x64)
    {
        (cLevel64x64, ) = PoolStorage.layout().getRealCLevel64x64(isCall);
    }

    /**
     * @inheritdoc IPoolView
     */
    function getSteepness64x64(bool isCallPool)
        external
        view
        override
        returns (int128)
    {
        if (isCallPool) {
            return PoolStorage.layout().steepnessUnderlying64x64;
        } else {
            return PoolStorage.layout().steepnessBase64x64;
        }
    }

    /**
     * @inheritdoc IPoolView
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
     * @inheritdoc IPoolView
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
     * @inheritdoc IPoolView
     */
    function getMinimumAmounts()
        external
        view
        override
        returns (uint256 minCallTokenAmount, uint256 minPutTokenAmount)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (_getMinimumAmount(l, true), _getMinimumAmount(l, false));
    }

    /**
     * @inheritdoc IPoolView
     */
    function getCapAmounts()
        external
        view
        override
        returns (uint256 callTokenCapAmount, uint256 putTokenCapAmount)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (_getPoolCapAmount(l, true), _getPoolCapAmount(l, false));
    }

    /**
     * @inheritdoc IPoolView
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
     * @inheritdoc IPoolView
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
     * @inheritdoc IPoolView
     */
    function getPremiaMining() external view override returns (address) {
        return PREMIA_MINING_ADDRESS;
    }

    /**
     * @inheritdoc IPoolView
     */
    function getDivestmentTimestamps(address account)
        external
        view
        override
        returns (
            uint256 callDivestmentTimestamp,
            uint256 putDivestmentTimestamp
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        callDivestmentTimestamp = l.divestmentTimestamps[account][true];
        putDivestmentTimestamp = l.divestmentTimestamps[account][false];
    }

    /**
     * @inheritdoc IERC1155Metadata
     * @dev SVG generated via external PremiaOptionNFTDisplay contract
     */
    function uri(uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        return
            IPremiaOptionNFTDisplay(NFT_DISPLAY_ADDRESS).tokenURI(
                address(this),
                tokenId
            );
    }
}
