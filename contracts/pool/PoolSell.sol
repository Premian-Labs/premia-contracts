// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {EnumerableSet, ERC1155EnumerableStorage} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155EnumerableStorage.sol";

import {ABDKMath64x64Token} from "../libraries/ABDKMath64x64Token.sol";

import {IPoolSell} from "./IPoolSell.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract PoolSell is IPoolSell, PoolInternal {
    using ABDKMath64x64 for int128;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address ivolOracle,
        address weth,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 feePremium64x64,
        int128 feeApy64x64
    )
        PoolInternal(
            ivolOracle,
            weth,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            feePremium64x64,
            feeApy64x64
        )
    {}

    /**
     * @inheritdoc IPoolSell
     */
    function setBuybackEnabled(bool state) external {
        PoolStorage.layout().setBuybackEnabled(state);
    }

    /**
     * @inheritdoc IPoolSell
     */
    function isBuybackEnabled(address account) external view returns (bool) {
        return PoolStorage.layout().isBuybackEnabled[account];
    }

    /**
     * @inheritdoc IPoolSell
     */
    function getAvailableBuybackLiquidity(
        uint64 maturity,
        int128 strike64x64,
        bool isCall
    ) external view returns (uint256) {
        uint256 shortTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        return _getAvailableBuybackLiquidity(shortTokenId);
    }

    /**
     * @inheritdoc IPoolSell
     */
    function sellQuote(
        address feePayer,
        uint64 maturity,
        int128 strike64x64,
        int128 spot64x64,
        uint256 contractSize,
        bool isCall
    ) external view returns (int128 baseCost64x64, int128 feeCost64x64) {
        return
            _quoteSalePrice(
                PoolStorage.QuoteArgsInternal(
                    feePayer,
                    maturity,
                    strike64x64,
                    spot64x64,
                    contractSize,
                    isCall
                )
            );
    }

    /**
     * @inheritdoc IPoolSell
     */
    function sell(
        uint64 maturity,
        int128 strike64x64,
        bool isCall,
        uint256 contractSize
    ) external {
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 baseCost;
        uint256 feeCost;

        {
            int128 newPrice64x64 = _update(l);

            (int128 baseCost64x64, int128 feeCost64x64) = _quoteSalePrice(
                PoolStorage.QuoteArgsInternal(
                    msg.sender,
                    maturity,
                    strike64x64,
                    newPrice64x64,
                    contractSize,
                    isCall
                )
            );

            baseCost = ABDKMath64x64Token.toDecimals(
                baseCost64x64,
                l.getTokenDecimals(isCall)
            );

            feeCost = ABDKMath64x64Token.toDecimals(
                feeCost64x64,
                l.getTokenDecimals(isCall)
            );
        }

        _burnShortTokenLoop(
            l,
            maturity,
            strike64x64,
            contractSize,
            baseCost,
            isCall,
            true
        );

        uint256 longTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, true),
            maturity,
            strike64x64
        );

        _burn(msg.sender, longTokenId, contractSize);

        _processAvailableFunds(
            msg.sender,
            baseCost - feeCost,
            isCall,
            true,
            true
        );

        _processAvailableFunds(
            FEE_RECEIVER_ADDRESS,
            feeCost,
            isCall,
            true,
            false
        );
    }
}
