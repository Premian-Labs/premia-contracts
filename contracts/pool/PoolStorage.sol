// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {EnumerableSet, ERC1155EnumerableStorage} from "@solidstate/contracts/token/ERC1155/ERC1155EnumerableStorage.sol";

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {ABDKMath64x64Token} from "../libraries/ABDKMath64x64Token.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {PoolWrite} from "./PoolWrite.sol";

library PoolStorage {
    enum TokenType {
        UNDERLYING_FREE_LIQ,
        BASE_FREE_LIQ,
        UNDERLYING_RESERVED_LIQ,
        BASE_RESERVED_LIQ,
        LONG_CALL,
        SHORT_CALL,
        LONG_PUT,
        SHORT_PUT
    }

    struct PoolSettings {
        address underlying;
        address base;
        address underlyingOracle;
        address baseOracle;
    }

    struct QuoteArgsInternal {
        address feePayer; // address of the fee payer
        uint64 maturity; // timestamp of option maturity
        int128 strike64x64; // 64x64 fixed point representation of strike price
        int128 spot64x64; // 64x64 fixed point representation of spot price
        int128 emaVarianceAnnualized64x64; // 64x64 fixed point representation of annualized variance
        uint256 contractSize; // size of option contract
        bool isCall; // true for call, false for put
    }

    struct BatchData {
        uint256 eta;
        uint256 totalPendingDeposits;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.Pool");

    struct Layout {
        // ERC20 token addresses
        address base;
        address underlying;
        // AggregatorV3Interface oracle addresses
        address baseOracle;
        address underlyingOracle;
        // token metadata
        uint8 underlyingDecimals;
        uint8 baseDecimals;
        int128 cLevelUnderlying64x64;
        int128 cLevelBase64x64;
        uint256 updatedAt;
        int128 emaLogReturns64x64;
        int128 emaVarianceAnnualized64x64;
        // User -> isCall -> depositedAt
        mapping(address => mapping(bool => uint256)) depositedAt;
        mapping(address => uint256) divestmentTimestamps;
        // doubly linked list of free liquidity intervals
        // isCall -> User -> User
        mapping(bool => mapping(address => address)) liquidityQueueAscending;
        mapping(bool => mapping(address => address)) liquidityQueueDescending;
        // TODO: enforced interval size for maturity (maturity % interval == 0)
        // updatable by owner

        // minimum resolution price bucket => price
        mapping(uint256 => int128) bucketPrices64x64;
        // sequence id (minimum resolution price bucket / 256) => price update sequence
        mapping(uint256 => uint256) priceUpdateSequences;
        // isCall -> batch data
        mapping(bool => BatchData) nextDeposits;
        // user -> batch timestamp -> isCall -> pending amount
        mapping(address => mapping(uint256 => mapping(bool => uint256))) pendingDeposits;
        EnumerableSet.UintSet tokenIds;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /**
     * @notice calculate ERC1155 token id for given option parameters
     * @param tokenType TokenType enum
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @return tokenId token id
     */
    function formatTokenId(
        TokenType tokenType,
        uint64 maturity,
        int128 strike64x64
    ) internal pure returns (uint256 tokenId) {
        // TODO: fix probably Hardhat issue related to usage of assembly
        // assembly {
        //   tokenId := add(shl(248, tokenType), add(shl(128, maturity), strike64x64))
        // }

        tokenId =
            (uint256(tokenType) << 248) +
            (uint256(maturity) << 128) +
            uint256(int256(strike64x64));
    }

    /**
     * @notice derive option maturity and strike price from ERC1155 token id
     * @param tokenId token id
     * @return tokenType TokenType enum
     * @return maturity timestamp of option maturity
     * @return strike64x64 option strike price
     */
    function parseTokenId(uint256 tokenId)
        internal
        pure
        returns (
            TokenType tokenType,
            uint64 maturity,
            int128 strike64x64
        )
    {
        assembly {
            tokenType := shr(248, tokenId)
            maturity := shr(128, tokenId)
            strike64x64 := tokenId
        }
    }

    function getTokenDecimals(Layout storage l, bool isCall)
        internal
        view
        returns (uint8 decimals)
    {
        decimals = isCall ? l.underlyingDecimals : l.baseDecimals;
    }

    function totalFreeLiquiditySupply64x64(Layout storage l, bool isCall)
        internal
        view
        returns (int128)
    {
        uint256 tokenId = formatTokenId(
            isCall ? TokenType.UNDERLYING_FREE_LIQ : TokenType.BASE_FREE_LIQ,
            0,
            0
        );

        return
            ABDKMath64x64Token.fromDecimals(
                ERC1155EnumerableStorage.layout().totalSupply[tokenId] -
                    l.nextDeposits[isCall].totalPendingDeposits,
                getTokenDecimals(l, isCall)
            );
    }

    function getReinvestmentStatus(Layout storage l, address account)
        internal
        view
        returns (bool)
    {
        uint256 timestamp = l.divestmentTimestamps[account];
        return timestamp == 0 || timestamp > block.timestamp;
    }

    function addUnderwriter(
        Layout storage l,
        address account,
        bool isCallPool
    ) internal {
        require(account != address(0));
        if (isInQueue(l, account, isCallPool)) return;

        mapping(address => address) storage desc = l.liquidityQueueDescending[
            isCallPool
        ];

        address last = desc[address(0)];

        l.liquidityQueueAscending[isCallPool][last] = account;
        desc[account] = last;
        desc[address(0)] = account;
    }

    function removeUnderwriter(
        Layout storage l,
        address account,
        bool isCallPool
    ) internal {
        require(account != address(0));
        if (!isInQueue(l, account, isCallPool)) return;

        mapping(address => address) storage asc = l.liquidityQueueAscending[
            isCallPool
        ];
        mapping(address => address) storage desc = l.liquidityQueueDescending[
            isCallPool
        ];

        address prev = desc[account];
        address next = asc[account];
        asc[prev] = next;
        desc[next] = prev;
        delete asc[account];
        delete desc[account];
    }

    function isInQueue(
        Layout storage l,
        address account,
        bool isCallPool
    ) internal view returns (bool) {
        mapping(address => address) storage asc = l.liquidityQueueAscending[
            isCallPool
        ];
        mapping(address => address) storage desc = l.liquidityQueueDescending[
            isCallPool
        ];

        return
            asc[address(0)] == account ||
            desc[address(0)] == account ||
            asc[account] != address(0);
        // No need to check desc[account]
    }

    function getCLevel(Layout storage l, bool isCall)
        internal
        view
        returns (int128 cLevel64x64)
    {
        cLevel64x64 = isCall ? l.cLevelUnderlying64x64 : l.cLevelBase64x64;
    }

    function setCLevel(
        Layout storage l,
        int128 oldLiquidity64x64,
        int128 newLiquidity64x64,
        bool isCallPool
    ) internal returns (int128 cLevel64x64) {
        cLevel64x64 = calculateCLevel(
            l,
            oldLiquidity64x64,
            newLiquidity64x64,
            isCallPool
        );

        if (isCallPool) {
            l.cLevelUnderlying64x64 = cLevel64x64;
        } else {
            l.cLevelBase64x64 = cLevel64x64;
        }
    }

    function calculateCLevel(
        Layout storage l,
        int128 oldLiquidity64x64,
        int128 newLiquidity64x64,
        bool isCallPool
    ) internal view returns (int128) {
        int128 cLevel64x64 = OptionMath.calculateCLevel(
            isCallPool ? l.cLevelUnderlying64x64 : l.cLevelBase64x64,
            oldLiquidity64x64,
            newLiquidity64x64,
            0x8000000000000000 // 64x64 fixed point representation of 0.5
        );

        return
            cLevel64x64 < 0xcccccccccccccccd
                ? int128(0xcccccccccccccccd)
                : cLevel64x64;
        // 0.8 min
    }

    function setOracles(
        Layout storage l,
        address baseOracle,
        address underlyingOracle
    ) internal {
        require(
            AggregatorV3Interface(baseOracle).decimals() ==
                AggregatorV3Interface(underlyingOracle).decimals(),
            "Pool: oracle decimals must match"
        );

        l.baseOracle = baseOracle;
        l.underlyingOracle = underlyingOracle;
    }

    function fetchPriceUpdate(Layout storage l)
        internal
        view
        returns (int128 price64x64)
    {
        int256 priceUnderlying = AggregatorInterface(l.underlyingOracle)
        .latestAnswer();
        int256 priceBase = AggregatorInterface(l.baseOracle).latestAnswer();

        return ABDKMath64x64.divi(priceUnderlying, priceBase);
    }

    /**
     * @notice set price update for current hourly bucket
     * @param l storage layout struct
     * @param timestamp timestamp to update
     * @param price64x64 64x64 fixed point representation of price
     */
    function setPriceUpdate(
        Layout storage l,
        uint256 timestamp,
        int128 price64x64
    ) internal {
        uint256 bucket = timestamp / (1 hours);
        l.bucketPrices64x64[bucket] = price64x64;
        l.priceUpdateSequences[bucket >> 8] += 1 << (255 - (bucket & 255));
    }

    /**
     * @notice get price update for hourly bucket corresponding to given timestamp
     * @param l storage layout struct
     * @param timestamp timestamp to query
     * @return 64x64 fixed point representation of price
     */
    function getPriceUpdate(Layout storage l, uint256 timestamp)
        internal
        view
        returns (int128)
    {
        return l.bucketPrices64x64[timestamp / (1 hours)];
    }

    /**
     * @notice get first price update available following given timestamp
     * @param l storage layout struct
     * @param timestamp timestamp to query
     * @return 64x64 fixed point representation of price
     */
    function getPriceUpdateAfter(Layout storage l, uint256 timestamp)
        internal
        view
        returns (int128)
    {
        // price updates are grouped into hourly buckets
        uint256 bucket = timestamp / (1 hours);
        // divide by 256 to get the index of the relevant price update sequence
        uint256 sequenceId = bucket >> 8;

        // get position within sequence relevant to current price update

        uint256 offset = bucket & 255;
        // shift to skip buckets from earlier in sequence
        uint256 sequence = (l.priceUpdateSequences[sequenceId] << offset) >>
            offset;

        // iterate through future sequences until a price update is found
        // sequence corresponding to current timestamp used as upper bound

        uint256 currentPriceUpdateSequenceId = block.timestamp / (256 hours);

        while (sequence == 0 && sequenceId <= currentPriceUpdateSequenceId) {
            sequence = l.priceUpdateSequences[++sequenceId];
        }

        // if no price update is found (sequence == 0) function will return 0
        // this should never occur, as each relevant external function triggers a price update

        // the most significant bit of the sequence corresponds to the offset of the relevant bucket

        uint256 msb;

        for (uint256 i = 128; i > 0; i >>= 1) {
            if (sequence >> i > 0) {
                msb += i;
                sequence >>= i;
            }
        }

        return l.bucketPrices64x64[((sequenceId + 1) << 8) - msb - 1];
    }

    function fromBaseToUnderlyingDecimals(Layout storage l, uint256 value)
        internal
        view
        returns (uint256)
    {
        int128 valueFixed64x64 = ABDKMath64x64Token.fromDecimals(
            value,
            l.baseDecimals
        );
        return
            ABDKMath64x64Token.toDecimals(
                valueFixed64x64,
                l.underlyingDecimals
            );
    }

    function fromUnderlyingToBaseDecimals(Layout storage l, uint256 value)
        internal
        view
        returns (uint256)
    {
        int128 valueFixed64x64 = ABDKMath64x64Token.fromDecimals(
            value,
            l.underlyingDecimals
        );
        return ABDKMath64x64Token.toDecimals(valueFixed64x64, l.baseDecimals);
    }
}
