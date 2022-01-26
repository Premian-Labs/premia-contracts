// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {EnumerableSet, ERC1155EnumerableStorage} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155EnumerableStorage.sol";
import {ERC1155BaseStorage} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseStorage.sol";

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
    {}

    /**
     * @inheritdoc IPoolSell
     */
    function setBuyBackEnabled(bool state) external {
        PoolStorage.Layout storage l = PoolStorage.layout();
        l.isBuyBackEnabled[msg.sender] = state;
    }

    /**
     * @inheritdoc IPoolSell
     */
    function isBuyBackEnabled(address account) external view returns (bool) {
        return PoolStorage.layout().isBuyBackEnabled[account];
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

    function _sellLoop(
        PoolStorage.Layout storage l,
        uint64 maturity,
        int128 strike64x64,
        bool isCall,
        uint256 contractSize,
        address[] memory buyers,
        uint256 sellPrice
    ) internal returns (uint256 amountFilled) {
        uint256 longTokenId = PoolStorage.formatTokenId(
            _getTokenType(isCall, true),
            maturity,
            strike64x64
        );

        uint256 shortTokenId = PoolStorage.formatTokenId(
            _getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        uint256 tokenAmount = isCall
            ? contractSize
            : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(contractSize));

        for (uint256 i = 0; i < buyers.length; i++) {
            if (!l.isBuyBackEnabled[buyers[i]]) continue;

            uint256 intervalContractSize;
            {
                uint256 maxAmount = ERC1155BaseStorage.layout().balances[
                    shortTokenId
                ][buyers[i]];

                if (maxAmount == 0) continue;

                if (maxAmount >= contractSize - amountFilled) {
                    intervalContractSize = contractSize - amountFilled;
                } else {
                    intervalContractSize = maxAmount;
                }
            }

            _burn(msg.sender, longTokenId, intervalContractSize);
            _burn(buyers[i], shortTokenId, intervalContractSize);

            uint256 intervalToken = (tokenAmount * intervalContractSize) /
                contractSize;
            uint256 intervalPremium = (sellPrice * intervalContractSize) /
                contractSize;

            uint256 tvlToSubtract;

            if (PoolStorage.layout().getReinvestmentStatus(buyers[i], isCall)) {
                _addToDepositQueue(
                    buyers[i],
                    intervalToken - intervalPremium,
                    isCall
                );
                tvlToSubtract = intervalPremium;
            } else {
                _mint(
                    buyers[i],
                    _getReservedLiquidityTokenId(isCall),
                    intervalToken - intervalPremium
                );
                tvlToSubtract = intervalToken;
            }

            _subUserTVL(PoolStorage.layout(), buyers[i], isCall, tvlToSubtract);

            amountFilled += intervalContractSize;

            if (amountFilled == contractSize) break;
        }

        return amountFilled;
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

            (int128 baseCost64x64, int128 feeCost64x64) = _sellQuote(
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

        require(amountFilled > 0, "no sell liq");

        baseCost = (baseCost * amountFilled) / contractSize;
        feeCost = (feeCost * amountFilled) / contractSize;

        _pushTo(msg.sender, _getPoolToken(isCall), baseCost - feeCost);
        _mint(
            FEE_RECEIVER_ADDRESS,
            _getReservedLiquidityTokenId(isCall),
            feeCost
        );
    }
}
