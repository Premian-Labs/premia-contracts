// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IPremiaOptionNFTDisplay} from "../interfaces/IPremiaOptionNFTDisplay.sol";
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
        address wrappedNativeToken,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 feePremium64x64,
        address exchangeHelper
    )
        PoolInternal(
            ivolOracle,
            wrappedNativeToken,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            feePremium64x64,
            exchangeHelper
        )
    {
        NFT_DISPLAY_ADDRESS = nftDisplay;
    }

    /**
     * @inheritdoc IPoolView
     */
    function getFeeReceiverAddress() external view returns (address) {
        return FEE_RECEIVER_ADDRESS;
    }

    /**
     * @inheritdoc IPoolView
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
     * @inheritdoc IPoolView
     */
    function getTokenIds() external view returns (uint256[] memory) {
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
    function getCLevel64x64(
        bool isCall
    ) external view returns (int128 cLevel64x64) {
        (cLevel64x64, ) = PoolStorage.layout().getRealPoolState(isCall);
    }

    /**
     * @inheritdoc IPoolView
     */
    function getApyFee64x64() external view returns (int128 apyFee64x64) {
        apyFee64x64 = PoolStorage.layout().getFeeApy64x64();
    }

    /**
     * @inheritdoc IPoolView
     */
    function getSteepness64x64(bool isCallPool) external view returns (int128) {
        if (isCallPool) {
            return PoolStorage.layout().steepnessUnderlying64x64;
        } else {
            return PoolStorage.layout().steepnessBase64x64;
        }
    }

    /**
     * @inheritdoc IPoolView
     */
    function getPrice64x64(uint256 timestamp) external view returns (int128) {
        return PoolStorage.layout().getPriceUpdate(timestamp);
    }

    /**
     * @inheritdoc IPoolView
     */
    function getPriceAfter64x64(
        uint256 timestamp
    ) external view returns (int128 spot64x64) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        spot64x64 = l.getPriceUpdateAfter(timestamp);

        if (spot64x64 == 0) {
            spot64x64 = l.fetchPriceUpdate();
        }
    }

    /**
     * @inheritdoc IPoolView
     */
    function getParametersForTokenId(
        uint256 tokenId
    ) external pure returns (PoolStorage.TokenType, uint64, int128) {
        return PoolStorage.parseTokenId(tokenId);
    }

    /**
     * @inheritdoc IPoolView
     */
    function getMinimumAmounts()
        external
        view
        returns (uint256 minCallTokenAmount, uint256 minPutTokenAmount)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (l.getMinimumAmount(true), l.getMinimumAmount(false));
    }

    /**
     * @inheritdoc IPoolView
     */
    function getUserTVL(
        address user
    ) external view returns (uint256 underlyingTVL, uint256 baseTVL) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (l.userTVL[user][true], l.userTVL[user][false]);
    }

    /**
     * @inheritdoc IPoolView
     */
    function getTotalTVL()
        external
        view
        returns (uint256 underlyingTVL, uint256 baseTVL)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (l.totalTVL[true], l.totalTVL[false]);
    }

    /**
     * @inheritdoc IPoolView
     */
    function getLiquidityQueuePosition(
        address account,
        bool isCallPool
    )
        external
        view
        returns (uint256 liquidityBeforePosition, uint256 positionSize)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 tokenId = _getFreeLiquidityTokenId(isCallPool);

        if (!l.isInQueue(account, isCallPool)) {
            liquidityBeforePosition = _totalSupply(tokenId);
        } else {
            mapping(address => address) storage asc = l.liquidityQueueAscending[
                isCallPool
            ];

            address depositor = asc[address(0)];

            while (depositor != account) {
                liquidityBeforePosition += _balanceOf(depositor, tokenId);
                depositor = asc[depositor];
            }

            positionSize = _balanceOf(depositor, tokenId);
        }
    }

    /**
     * @inheritdoc IPoolView
     */
    function getPremiaMining() external view returns (address) {
        return PREMIA_MINING_ADDRESS;
    }

    /**
     * @inheritdoc IPoolView
     */
    function getDivestmentTimestamps(
        address account
    )
        external
        view
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
     * @inheritdoc IPoolView
     */
    function getFeesReserved(
        address account,
        uint256 shortTokenId
    ) external view returns (uint256 feesReserved) {
        feesReserved = PoolStorage.layout().feesReserved[account][shortTokenId];
    }

    /**
     * @inheritdoc IERC1155Metadata
     * @dev SVG generated via external PremiaOptionNFTDisplay contract
     */
    function uri(uint256 tokenId) external view returns (string memory) {
        return
            IPremiaOptionNFTDisplay(NFT_DISPLAY_ADDRESS).tokenURI(
                address(this),
                tokenId
            );
    }

    /**
     * @inheritdoc IPoolView
     */
    function getSpotOffset64x64()
        external
        view
        returns (int128 spotOffset64x64)
    {
        spotOffset64x64 = PoolStorage.layout().spotOffset64x64;
    }

    /**
     * @inheritdoc IPoolView
     */
    function getExchangeHelper()
        external
        view
        returns (address exchangeHelper)
    {
        exchangeHelper = EXCHANGE_HELPER;
    }
}
