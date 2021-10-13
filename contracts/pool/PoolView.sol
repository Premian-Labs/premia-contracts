// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {ERC1155BaseStorage} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseStorage.sol";
import {ERC1155EnumerableStorage} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155EnumerableStorage.sol";
import {PoolStorage} from "./PoolStorage.sol";

import {IPoolView} from "./IPoolView.sol";
import {PoolInternal} from "./PoolInternal.sol";

import {IPremiaOptionNFTDisplay} from "../interface/IPremiaOptionNFTDisplay.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolView is IPoolView, PoolInternal {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
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
     * @notice get fee receiver address
     * @dev called by PremiaMakerKeeper
     * @return fee receiver address
     */
    function getFeeReceiverAddress() external view override returns (address) {
        return FEE_RECEIVER_ADDRESS;
    }

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
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (_getMinimumAmount(l, true), _getMinimumAmount(l, false));
    }

    /**
     * @notice get deposit cap amounts
     * @return callTokenCapAmount call pool deposit cap
     * @return putTokenCapAmount put pool deposit cap
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
     * @notice get the addres of PremiaMining contract
     * @return address of PremiaMining contract
     */
    function getPremiaMining() external view override returns (address) {
        return PREMIA_MINING_ADDRESS;
    }

    /**
     * @notice get the gradual divestment timestamps of a user
     * @param account user account
     * @return callDivestmentTimestamp gradual divestment timestamp of the user for the call pool
     * @return putDivestmentTimestamp gradual divestment timestamp of the user for the put pool
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

    function isBuyBackEnabled(address account)
        external
        view
        override
        returns (bool)
    {
        return PoolStorage.layout().isBuyBackEnabled[account];
    }

    /**
     * @notice get list of underwriters with buyback enabled for a specific shortTokenId
     * @param shortTokenId the long token id
     * @return buyers list of underwriters with buyback enabled for this shortTokenId
     * @return amounts amounts of options underwritten by each LP with buyback enabled
     */
    function getBuyers(uint256 shortTokenId)
        external
        view
        override
        returns (address[] memory buyers, uint256[] memory amounts)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        ERC1155EnumerableStorage.Layout
            storage erc1155EnumerableLayout = ERC1155EnumerableStorage.layout();

        uint256 length = erc1155EnumerableLayout
            .accountsByToken[shortTokenId]
            .length();
        uint256 i = 0;

        buyers = new address[](length);
        amounts = new uint256[](length);

        for (uint256 j = 0; j < length; j++) {
            address lp = erc1155EnumerableLayout
                .accountsByToken[shortTokenId]
                .at(j);
            if (l.isBuyBackEnabled[lp]) {
                buyers[i] = lp;
                amounts[i] = ERC1155BaseStorage.layout().balances[shortTokenId][
                    lp
                ];
                i++;
            }
        }

        // Reduce array size
        if (length > 0 && i < length - 1) {
            assembly {
                mstore(buyers, sub(mload(buyers), sub(length, i)))
                mstore(amounts, sub(mload(amounts), sub(length, i)))
            }
        }
    }

    /**
     * @notice Returns an URI for a given token ID
     * @param tokenId an option token id
     * @return The token URI
     */
    function tokenURI(uint256 tokenId)
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
