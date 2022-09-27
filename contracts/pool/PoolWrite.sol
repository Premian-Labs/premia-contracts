// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ABDKMath64x64Token} from "@solidstate/abdk-math-extensions/contracts/ABDKMath64x64Token.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ERC1155BaseStorage} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseStorage.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

import {PoolInternal} from "./PoolInternal.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {IPoolWrite} from "./IPoolWrite.sol";
import {IPoolInternal} from "./IPoolInternal.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolWrite is IPoolWrite, PoolInternal {
    using SafeERC20 for IERC20;
    using ABDKMath64x64 for int128;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address ivolOracle,
        address wrappedNativeToken,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 feePremium64x64,
        address exchangeProxy
    )
        PoolInternal(
            ivolOracle,
            wrappedNativeToken,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            feePremium64x64,
            exchangeProxy
        )
    {}

    /**
     * @inheritdoc IPoolWrite
     */
    function quote(
        address feePayer,
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall
    )
        external
        view
        returns (
            int128 baseCost64x64,
            int128 feeCost64x64,
            int128 cLevel64x64,
            int128 slippageCoefficient64x64
        )
    {
        int128 spot64x64;

        PoolStorage.Layout storage l = PoolStorage.layout();
        if (l.updatedAt != block.timestamp) {
            spot64x64 = l.fetchPriceUpdate();
        } else {
            spot64x64 = l.getPriceUpdate(block.timestamp);
        }

        PoolStorage.QuoteResultInternal
            memory quoteResult = _quotePurchasePrice(
                PoolStorage.QuoteArgsInternal(
                    feePayer,
                    maturity,
                    strike64x64,
                    spot64x64,
                    contractSize,
                    isCall
                )
            );

        return (
            quoteResult.baseCost64x64,
            quoteResult.feeCost64x64,
            quoteResult.cLevel64x64,
            quoteResult.slippageCoefficient64x64
        );
    }

    /**
     * @inheritdoc IPoolWrite
     */
    function purchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost
    ) external payable returns (uint256 baseCost, uint256 feeCost) {
        (baseCost, feeCost) = _verifyAndPurchase(
            maturity,
            strike64x64,
            contractSize,
            isCall,
            maxCost
        );
        PoolStorage.Layout storage l = PoolStorage.layout();
        _pullFrom(l, msg.sender, baseCost + feeCost, isCall, true);
    }

    /**
     * @inheritdoc IPoolWrite
     */
    function swapAndPurchase(
        IPoolInternal.SwapArgs memory s,
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall
    ) public payable returns (uint256 baseCost, uint256 feeCost) {
        address tokenOut = PoolStorage.layout().getPoolToken(isCall);

        uint256 creditAmount = _swapForPoolTokens(s, tokenOut);

        // if baseCost + feeCost > creditAmount, it will revert
        (baseCost, feeCost) = _verifyAndPurchase(
            maturity,
            strike64x64,
            contractSize,
            isCall,
            creditAmount
        );
        uint256 totalCost = baseCost + feeCost;
        if (creditAmount > totalCost) {
            // refund extra token got from the swap.
            _pushTo(s.refundAddress, tokenOut, creditAmount - totalCost);
        }
    }

    /**
     * @inheritdoc IPoolWrite
     */
    function writeFrom(
        address underwriter,
        address longReceiver,
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall
    ) external payable returns (uint256 longTokenId, uint256 shortTokenId) {
        require(
            msg.sender == underwriter ||
                ERC1155BaseStorage.layout().operatorApprovals[underwriter][
                    msg.sender
                ],
            "not approved"
        );

        longTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, true),
            maturity,
            strike64x64
        );
        shortTokenId = PoolStorage.formatTokenId(
            PoolStorage.getTokenType(isCall, false),
            maturity,
            strike64x64
        );

        PoolStorage.Layout storage l = PoolStorage.layout();
        int128 utilization64x64 = l.getUtilization64x64(isCall);

        _verifyPurchase(maturity, strike64x64, isCall, _update(l));

        Interval memory interval;

        interval.contractSize = contractSize;

        interval.tokenAmount = l.contractSizeToBaseTokenAmount(
            contractSize,
            strike64x64,
            isCall
        );

        interval.apyFee = _calculateApyFee(
            l,
            shortTokenId,
            interval.tokenAmount,
            maturity
        );

        interval.payment = interval.tokenAmount + interval.apyFee;

        _pullFrom(l, underwriter, interval.payment, isCall, true);

        // mint long option token for designated receiver
        _mint(longReceiver, longTokenId, contractSize);

        _mintShortTokenInterval(
            l,
            underwriter,
            longReceiver,
            shortTokenId,
            interval,
            isCall,
            utilization64x64
        );
    }

    /**
     * @inheritdoc IPoolWrite
     */
    function update() external {
        _update(PoolStorage.layout());
    }

    /**
     * @notice verify parameters and purchase option
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param contractSize size of option contract
     * @param isCall true for call, false for put
     * @param maxCost maximum acceptable cost after accounting for slippage
     * @return baseCost quantity of tokens required to purchase long position
     * @return feeCost quantity of tokens required to pay fees
     */
    function _verifyAndPurchase(
        uint64 maturity,
        int128 strike64x64,
        uint256 contractSize,
        bool isCall,
        uint256 maxCost
    ) internal returns (uint256 baseCost, uint256 feeCost) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        int128 newPrice64x64 = _update(l);

        _verifyPurchase(maturity, strike64x64, isCall, newPrice64x64);

        (baseCost, feeCost) = _purchase(
            l,
            msg.sender,
            maturity,
            strike64x64,
            isCall,
            contractSize,
            newPrice64x64
        );

        uint256 amount = baseCost + feeCost;

        require(amount <= maxCost, "excess slipp");
    }

    /**
     * @notice verify option parameters before writing
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param isCall true for call, false for put
     * @param spot64x64 64x64 fixed point representation of spot price
     */
    function _verifyPurchase(
        uint64 maturity,
        int128 strike64x64,
        bool isCall,
        int128 spot64x64
    ) internal view {
        require(maturity >= block.timestamp + (1 days), "exp < 1 day");
        require(maturity < block.timestamp + (91 days), "exp > 90 days");
        require(maturity % (8 hours) == 0, "exp must be 8-hour increment");

        if (isCall) {
            require(
                strike64x64 <= spot64x64 << 1 &&
                    strike64x64 >= (spot64x64 * 8) / 10,
                "strike out of range"
            );
        } else {
            require(
                strike64x64 <= (spot64x64 * 12) / 10 &&
                    strike64x64 >= spot64x64 >> 1,
                "strike out of range"
            );
        }
    }
}
