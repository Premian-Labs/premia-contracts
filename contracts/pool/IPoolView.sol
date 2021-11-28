// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {IERC1155Metadata} from "@solidstate/contracts/token/ERC1155/metadata/IERC1155Metadata.sol";

import {PoolStorage} from "./PoolStorage.sol";

/**
 * @notice Pool view function interface
 */
interface IPoolView is IERC1155Metadata {
    /**
     * @notice get fee receiver address
     * @dev called by PremiaMakerKeeper
     * @return fee receiver address
     */
    function getFeeReceiverAddress() external view returns (address);

    /**
     * @notice get fundamental pool attributes
     * @return structured PoolSettings
     */
    function getPoolSettings()
        external
        view
        returns (PoolStorage.PoolSettings memory);

    /**
     * @notice get the list of all token ids in circulation
     * @return list of token ids
     */
    function getTokenIds() external view returns (uint256[] memory);

    /**
     * @notice get current C-Level, accounting for unrealized decay and pending deposits
     * @param isCall whether query is for call or put pool
     * @return cLevel64x64 64x64 fixed point representation of C-Level
     */
    function getCLevel64x64(bool isCall) external view returns (int128);

    /**
     * @notice get steepness coefficient
     * @param isCall whether query is for call or put pool
     * @return 64x64 fixed point representation of C steepness of Pool
     */
    function getSteepness64x64(bool isCall) external view returns (int128);

    /**
     * @notice get oracle price at timestamp
     * @param timestamp timestamp to query
     * @return 64x64 fixed point representation of price
     */
    function getPrice(uint256 timestamp) external view returns (int128);

    /**
     * @notice get parameters for token id
     * @param tokenId token id to query
     * @return token type enum
     * @return maturity
     * @return 64x64 fixed point representation of strike price
     */
    function getParametersForTokenId(uint256 tokenId)
        external
        pure
        returns (
            PoolStorage.TokenType,
            uint64,
            int128
        );

    /**
     * @notice get minimum purchase and interval amounts
     * @return minCallTokenAmount minimum call pool amount
     * @return minPutTokenAmount minimum put pool amount
     */
    function getMinimumAmounts()
        external
        view
        returns (uint256 minCallTokenAmount, uint256 minPutTokenAmount);

    /**
     * @notice get deposit cap amounts
     * @return callTokenCapAmount call pool deposit cap
     * @return putTokenCapAmount put pool deposit cap
     */
    function getCapAmounts()
        external
        view
        returns (uint256 callTokenCapAmount, uint256 putTokenCapAmount);

    /**
     * @notice get TVL (total value locked) for given address
     * @param account address whose TVL to query
     * @return underlyingTVL user total value locked in call pool (in underlying token amount)
     * @return baseTVL user total value locked in put pool (in base token amount)
     */
    function getUserTVL(address account)
        external
        view
        returns (uint256 underlyingTVL, uint256 baseTVL);

    /**
     * @notice get TVL (total value locked) of entire Pool
     * @return underlyingTVL total value locked in call pool (in underlying token amount)
     * @return baseTVL total value locked in put pool (in base token amount)
     */
    function getTotalTVL()
        external
        view
        returns (uint256 underlyingTVL, uint256 baseTVL);

    /**
     * @notice get the addres of PremiaMining contract
     * @return address of PremiaMining contract
     */
    function getPremiaMining() external view returns (address);

    /**
     * @notice get the gradual divestment timestamps of a user
     * @param account address whose divestment timestamps to query
     * @return callDivestmentTimestamp gradual divestment timestamp of the user for the call pool
     * @return putDivestmentTimestamp gradual divestment timestamp of the user for the put pool
     */
    function getDivestmentTimestamps(address account)
        external
        view
        returns (
            uint256 callDivestmentTimestamp,
            uint256 putDivestmentTimestamp
        );
}
