// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {EnumerableSet, ERC1155EnumerableStorage} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155EnumerableStorage.sol";

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {ABDKMath64x64Token} from "../libraries/ABDKMath64x64Token.sol";
import {OptionMath} from "../libraries/OptionMath.sol";

library PoolStorage {
    using ABDKMath64x64 for int128;
    using PoolStorage for PoolStorage.Layout;

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
        uint256 contractSize; // size of option contract
        bool isCall; // true for call, false for put
    }

    struct QuoteResultInternal {
        int128 baseCost64x64; // 64x64 fixed point representation of option cost denominated in underlying currency (without fee)
        int128 feeCost64x64; // 64x64 fixed point representation of option fee cost denominated in underlying currency for call, or base currency for put
        int128 cLevel64x64; // 64x64 fixed point representation of C-Level of Pool after purchase
        int128 slippageCoefficient64x64; // 64x64 fixed point representation of slippage coefficient for given order size
    }

    struct BatchData {
        uint256 eta;
        uint256 totalPendingDeposits;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.Pool");

    uint256 private constant C_DECAY_BUFFER = 12 hours;
    uint256 private constant C_DECAY_INTERVAL = 4 hours;

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
        // minimum amounts
        uint256 baseMinimum;
        uint256 underlyingMinimum;
        // deposit caps
        uint256 basePoolCap;
        uint256 underlyingPoolCap;
        // market state
        int128 _deprecated_steepness64x64;
        int128 cLevelBase64x64;
        int128 cLevelUnderlying64x64;
        uint256 cLevelBaseUpdatedAt;
        uint256 cLevelUnderlyingUpdatedAt;
        uint256 updatedAt;
        // User -> isCall -> depositedAt
        mapping(address => mapping(bool => uint256)) depositedAt;
        mapping(address => mapping(bool => uint256)) divestmentTimestamps;
        // doubly linked list of free liquidity intervals
        // isCall -> User -> User
        mapping(bool => mapping(address => address)) liquidityQueueAscending;
        mapping(bool => mapping(address => address)) liquidityQueueDescending;
        // minimum resolution price bucket => price
        mapping(uint256 => int128) bucketPrices64x64;
        // sequence id (minimum resolution price bucket / 256) => price update sequence
        mapping(uint256 => uint256) priceUpdateSequences;
        // isCall -> batch data
        mapping(bool => BatchData) nextDeposits;
        // user -> batch timestamp -> isCall -> pending amount
        mapping(address => mapping(uint256 => mapping(bool => uint256))) pendingDeposits;
        EnumerableSet.UintSet tokenIds;
        // user -> isCallPool -> total value locked of user (Used for liquidity mining)
        mapping(address => mapping(bool => uint256)) userTVL;
        // isCallPool -> total value locked
        mapping(bool => uint256) totalTVL;
        // steepness values
        int128 steepnessBase64x64;
        int128 steepnessUnderlying64x64;
        // APY fee tracking
        // underwriter -> shortTokenId -> amount
        mapping(address => mapping(uint256 => uint256)) feesReserved;
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

    function getTokenType(bool isCall, bool isLong)
        internal
        pure
        returns (TokenType tokenType)
    {
        if (isCall) {
            tokenType = isLong ? TokenType.LONG_CALL : TokenType.SHORT_CALL;
        } else {
            tokenType = isLong ? TokenType.LONG_PUT : TokenType.SHORT_PUT;
        }
    }

    function getPoolToken(Layout storage l, bool isCall)
        internal
        view
        returns (address token)
    {
        token = isCall ? l.underlying : l.base;
    }

    function getTokenDecimals(Layout storage l, bool isCall)
        internal
        view
        returns (uint8 decimals)
    {
        decimals = isCall ? l.underlyingDecimals : l.baseDecimals;
    }

    function getMinimumAmount(Layout storage l, bool isCall)
        internal
        view
        returns (uint256 minimumAmount)
    {
        minimumAmount = isCall ? l.underlyingMinimum : l.baseMinimum;
    }

    function getPoolCapAmount(Layout storage l, bool isCall)
        internal
        view
        returns (uint256 poolCapAmount)
    {
        poolCapAmount = isCall ? l.underlyingPoolCap : l.basePoolCap;
    }

    /**
     * @notice get the total supply of free liquidity tokens, minus pending deposits
     * @param l storage layout struct
     * @param isCall whether query is for call or put pool
     * @return 64x64 fixed point representation of total free liquidity
     */
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
                    l.totalPendingDeposits(isCall),
                l.getTokenDecimals(isCall)
            );
    }

    function getReinvestmentStatus(
        Layout storage l,
        address account,
        bool isCallPool
    ) internal view returns (bool) {
        uint256 timestamp = l.divestmentTimestamps[account][isCallPool];
        return timestamp == 0 || timestamp > block.timestamp;
    }

    function addUnderwriter(
        Layout storage l,
        address account,
        bool isCallPool
    ) internal {
        require(account != address(0));

        mapping(address => address) storage asc = l.liquidityQueueAscending[
            isCallPool
        ];
        mapping(address => address) storage desc = l.liquidityQueueDescending[
            isCallPool
        ];

        if (_isInQueue(account, asc, desc)) return;

        address last = desc[address(0)];

        asc[last] = account;
        desc[account] = last;
        desc[address(0)] = account;
    }

    function removeUnderwriter(
        Layout storage l,
        address account,
        bool isCallPool
    ) internal {
        require(account != address(0));

        mapping(address => address) storage asc = l.liquidityQueueAscending[
            isCallPool
        ];
        mapping(address => address) storage desc = l.liquidityQueueDescending[
            isCallPool
        ];

        if (!_isInQueue(account, asc, desc)) return;

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

        return _isInQueue(account, asc, desc);
    }

    function _isInQueue(
        address account,
        mapping(address => address) storage asc,
        mapping(address => address) storage desc
    ) private view returns (bool) {
        return asc[account] != address(0) || desc[address(0)] == account;
    }

    /**
     * @notice get current C-Level, without accounting for pending adjustments
     * @param l storage layout struct
     * @param isCall whether query is for call or put pool
     * @return cLevel64x64 64x64 fixed point representation of C-Level
     */
    function getRawCLevel64x64(Layout storage l, bool isCall)
        internal
        view
        returns (int128 cLevel64x64)
    {
        cLevel64x64 = isCall ? l.cLevelUnderlying64x64 : l.cLevelBase64x64;
    }

    /**
     * @notice get current C-Level, accounting for unrealized decay
     * @param l storage layout struct
     * @param isCall whether query is for call or put pool
     * @return cLevel64x64 64x64 fixed point representation of C-Level
     */
    function getDecayAdjustedCLevel64x64(Layout storage l, bool isCall)
        internal
        view
        returns (int128 cLevel64x64)
    {
        // get raw C-Level from storage
        cLevel64x64 = l.getRawCLevel64x64(isCall);

        // account for C-Level decay
        cLevel64x64 = l.applyCLevelDecayAdjustment(cLevel64x64, isCall);
    }

    /**
     * @notice get updated C-Level and pool liquidity level, accounting for decay and pending deposits
     * @param l storage layout struct
     * @param isCall whether to update C-Level for call or put pool
     * @return cLevel64x64 64x64 fixed point representation of C-Level
     * @return liquidity64x64 64x64 fixed point representation of new liquidity amount
     */
    function getRealPoolState(Layout storage l, bool isCall)
        internal
        view
        returns (int128 cLevel64x64, int128 liquidity64x64)
    {
        PoolStorage.BatchData storage batchData = l.nextDeposits[isCall];

        int128 oldCLevel64x64 = l.getDecayAdjustedCLevel64x64(isCall);
        int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

        if (
            batchData.totalPendingDeposits > 0 &&
            batchData.eta != 0 &&
            block.timestamp >= batchData.eta
        ) {
            liquidity64x64 = ABDKMath64x64Token
                .fromDecimals(
                    batchData.totalPendingDeposits,
                    l.getTokenDecimals(isCall)
                )
                .add(oldLiquidity64x64);

            cLevel64x64 = l.applyCLevelLiquidityChangeAdjustment(
                oldCLevel64x64,
                oldLiquidity64x64,
                liquidity64x64,
                isCall
            );
        } else {
            cLevel64x64 = oldCLevel64x64;
            liquidity64x64 = oldLiquidity64x64;
        }
    }

    /**
     * @notice calculate updated C-Level, accounting for unrealized decay
     * @param l storage layout struct
     * @param oldCLevel64x64 64x64 fixed point representation pool C-Level before accounting for decay
     * @param isCall whether query is for call or put pool
     * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after accounting for decay
     */
    function applyCLevelDecayAdjustment(
        Layout storage l,
        int128 oldCLevel64x64,
        bool isCall
    ) internal view returns (int128 cLevel64x64) {
        uint256 timeElapsed = block.timestamp -
            (isCall ? l.cLevelUnderlyingUpdatedAt : l.cLevelBaseUpdatedAt);

        // do not apply C decay if less than 24 hours have elapsed

        if (timeElapsed > C_DECAY_BUFFER) {
            timeElapsed -= C_DECAY_BUFFER;
        } else {
            return oldCLevel64x64;
        }

        int128 timeIntervalsElapsed64x64 = ABDKMath64x64.divu(
            timeElapsed,
            C_DECAY_INTERVAL
        );

        uint256 tokenId = formatTokenId(
            isCall ? TokenType.UNDERLYING_FREE_LIQ : TokenType.BASE_FREE_LIQ,
            0,
            0
        );

        uint256 tvl = l.totalTVL[isCall];

        int128 utilization = ABDKMath64x64.divu(
            tvl -
                (ERC1155EnumerableStorage.layout().totalSupply[tokenId] -
                    l.totalPendingDeposits(isCall)),
            tvl
        );

        return
            OptionMath.calculateCLevelDecay(
                OptionMath.CalculateCLevelDecayArgs(
                    timeIntervalsElapsed64x64,
                    oldCLevel64x64,
                    utilization,
                    0xb333333333333333, // 0.7
                    0xe666666666666666, // 0.9
                    0x10000000000000000, // 1.0
                    0x10000000000000000, // 1.0
                    0xe666666666666666, // 0.9
                    0x56fc2a2c515da32ea // 2e
                )
            );
    }

    /**
     * @notice calculate updated C-Level, accounting for change in liquidity
     * @param l storage layout struct
     * @param oldCLevel64x64 64x64 fixed point representation pool C-Level before accounting for liquidity change
     * @param oldLiquidity64x64 64x64 fixed point representation of previous liquidity
     * @param newLiquidity64x64 64x64 fixed point representation of current liquidity
     * @param isCallPool whether to update C-Level for call or put pool
     * @return cLevel64x64 64x64 fixed point representation of C-Level
     */
    function applyCLevelLiquidityChangeAdjustment(
        Layout storage l,
        int128 oldCLevel64x64,
        int128 oldLiquidity64x64,
        int128 newLiquidity64x64,
        bool isCallPool
    ) internal view returns (int128 cLevel64x64) {
        int128 steepness64x64 = isCallPool
            ? l.steepnessUnderlying64x64
            : l.steepnessBase64x64;

        // fallback to deprecated storage value if side-specific value is not set
        if (steepness64x64 == 0) steepness64x64 = l._deprecated_steepness64x64;

        cLevel64x64 = OptionMath.calculateCLevel(
            oldCLevel64x64,
            oldLiquidity64x64,
            newLiquidity64x64,
            steepness64x64
        );

        if (cLevel64x64 < 0xb333333333333333) {
            cLevel64x64 = int128(0xb333333333333333); // 64x64 fixed point representation of 0.7
        }
    }

    /**
     * @notice set C-Level to arbitrary pre-calculated value
     * @param cLevel64x64 new C-Level of pool
     * @param isCallPool whether to update C-Level for call or put pool
     */
    function setCLevel(
        Layout storage l,
        int128 cLevel64x64,
        bool isCallPool
    ) internal {
        if (isCallPool) {
            l.cLevelUnderlying64x64 = cLevel64x64;
            l.cLevelUnderlyingUpdatedAt = block.timestamp;
        } else {
            l.cLevelBase64x64 = cLevel64x64;
            l.cLevelBaseUpdatedAt = block.timestamp;
        }
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
     * @notice set price update for hourly bucket corresponding to given timestamp
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

    function totalPendingDeposits(Layout storage l, bool isCallPool)
        internal
        view
        returns (uint256)
    {
        return l.nextDeposits[isCallPool].totalPendingDeposits;
    }

    function pendingDepositsOf(
        Layout storage l,
        address account,
        bool isCallPool
    ) internal view returns (uint256) {
        return
            l.pendingDeposits[account][l.nextDeposits[isCallPool].eta][
                isCallPool
            ];
    }

    function baseTokenAmountToContractSize(
        Layout storage l,
        uint256 liquidity,
        int128 price64x64
    ) internal view returns (uint256 contractSize) {
        uint256 value = price64x64.inv().mulu(liquidity);

        int128 valueFixed64x64 = ABDKMath64x64Token.fromDecimals(
            value,
            l.baseDecimals
        );
        contractSize = ABDKMath64x64Token.toDecimals(
            valueFixed64x64,
            l.underlyingDecimals
        );
    }

    function contractSizeToBaseTokenAmount(
        Layout storage l,
        uint256 contractSize,
        int128 price64x64
    ) internal view returns (uint256 liquidity) {
        uint256 value = price64x64.mulu(contractSize);

        int128 value64x64 = ABDKMath64x64Token.fromDecimals(
            value,
            l.underlyingDecimals
        );

        liquidity = ABDKMath64x64Token.toDecimals(value64x64, l.baseDecimals);
    }
}
