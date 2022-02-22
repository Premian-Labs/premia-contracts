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
    function getBuyers(uint256 shortTokenId)
        external
        view
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
            if (l.isBuybackEnabled[lp]) {
                buyers[i] = lp;
                amounts[i] = _balanceOf(lp, shortTokenId);
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

    function _sellLoop(
        PoolStorage.Layout storage l,
        uint64 maturity,
        int128 strike64x64,
        bool isCall,
        uint256 contractSize,
        address[] memory buyers,
        uint256 sellPrice
    ) internal returns (uint256 amountFilled) {
        uint256 shortTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        uint256 tokenAmount = l.contractSizeToBaseTokenAmount(
            contractSize,
            strike64x64,
            isCall
        );

        // calculate unconsumed APY fee so that it may be refunded

        uint256 apyFee = _calculateApyFee(
            l,
            shortTokenId,
            tokenAmount,
            maturity
        );

        for (uint256 i = 0; i < buyers.length && contractSize > 0; i++) {
            address underwriter = buyers[i];

            if (!l.isBuybackEnabled[underwriter]) continue;

            Interval memory interval;

            // amount of liquidity provided by underwriter
            interval.contractSize = _balanceOf(underwriter, shortTokenId);

            // if underwriter has no liquidity, skip
            // this should not be necessary because 0 value will prevent meaningful operations

            if (interval.contractSize == 0) continue;

            // truncate interval if underwriter has excess short position size

            if (interval.contractSize > contractSize)
                interval.contractSize = contractSize;

            // calculate derived interval variables

            interval.tokenAmount =
                (tokenAmount * interval.contractSize) /
                contractSize;
            interval.payment =
                (sellPrice * interval.contractSize) /
                contractSize;
            interval.apyFee = (apyFee * interval.contractSize) / contractSize;

            _burnShortTokenInterval(
                l,
                underwriter,
                shortTokenId,
                interval,
                isCall
            );

            contractSize -= interval.contractSize;
            tokenAmount -= interval.tokenAmount;
            sellPrice -= interval.payment;
            apyFee -= interval.apyFee;

            amountFilled += interval.contractSize;
        }

        return amountFilled;
    }

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
        uint256 contractSize,
        address[] memory buyers
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

        uint256 amountFilled = _sellLoop(
            l,
            maturity,
            strike64x64,
            isCall,
            contractSize,
            buyers,
            baseCost
        );

        uint256 longTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, true),
            maturity,
            strike64x64
        );

        _burn(msg.sender, longTokenId, amountFilled);

        require(amountFilled > 0, "no sell liq");

        baseCost = (baseCost * amountFilled) / contractSize;
        feeCost = (feeCost * amountFilled) / contractSize;

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
