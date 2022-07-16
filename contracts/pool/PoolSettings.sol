// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

import {IPoolSettings} from "./IPoolSettings.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {PoolStorage} from "./PoolStorage.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolSettings is IPoolSettings, PoolInternal {
    using PoolStorage for PoolStorage.Layout;
    using ABDKMath64x64 for int128;

    struct APYFeeData {
        address underwriter;
        uint256 shortTokenId;
        bool isCallPool;
        int128 feeDiscount64x64;
        bool divest;
    }

    constructor(
        address ivolOracle,
        address wrappedNativeToken,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 feePremium64x64
    )
        PoolInternal(
            ivolOracle,
            wrappedNativeToken,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            feePremium64x64
        )
    {}

    function processApyFees(APYFeeData[] calldata apyFeeData)
        external
        onlyProtocolOwner
    {
        unchecked {
            PoolStorage.Layout storage l = PoolStorage.layout();

            uint256 callFeesPaid;
            uint256 putFeesPaid;

            for (uint256 i; i < apyFeeData.length; i++) {
                APYFeeData memory data = apyFeeData[i];

                address underwriter = data.underwriter;
                uint256 shortTokenId = data.shortTokenId;
                bool isCallPool = data.isCallPool;

                uint256 feesReserved = l.feesReserved[underwriter][
                    shortTokenId
                ];
                delete l.feesReserved[underwriter][shortTokenId];

                uint256 rebate = data.feeDiscount64x64.mulu(feesReserved);
                uint256 feesPaid = feesReserved - rebate;

                _processAvailableFunds(
                    underwriter,
                    rebate,
                    isCallPool,
                    data.divest,
                    false
                );

                if (isCallPool) {
                    callFeesPaid += feesPaid;
                } else {
                    putFeesPaid += feesPaid;
                }

                emit APYFeePaid(underwriter, shortTokenId, feesPaid);
            }

            _processAvailableFunds(
                FEE_RECEIVER_ADDRESS,
                callFeesPaid,
                true,
                true,
                false
            );

            _processAvailableFunds(
                FEE_RECEIVER_ADDRESS,
                putFeesPaid,
                false,
                true,
                false
            );
        }
    }

    /**
     * @inheritdoc IPoolSettings
     */
    function setMinimumAmounts(uint256 baseMinimum, uint256 underlyingMinimum)
        external
        onlyProtocolOwner
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        l.baseMinimum = baseMinimum;
        l.underlyingMinimum = underlyingMinimum;
    }

    /**
     * @inheritdoc IPoolSettings
     */
    function setSteepness64x64(int128 steepness64x64, bool isCallPool)
        external
        onlyProtocolOwner
    {
        if (isCallPool) {
            PoolStorage.layout().steepnessUnderlying64x64 = steepness64x64;
        } else {
            PoolStorage.layout().steepnessBase64x64 = steepness64x64;
        }

        emit UpdateSteepness(steepness64x64, isCallPool);
    }

    /**
     * @inheritdoc IPoolSettings
     */
    function setCLevel64x64(int128 cLevel64x64, bool isCallPool)
        external
        onlyProtocolOwner
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        l.setCLevel(cLevel64x64, isCallPool);

        int128 liquidity64x64 = l.totalFreeLiquiditySupply64x64(isCallPool);

        emit UpdateCLevel(
            isCallPool,
            cLevel64x64,
            liquidity64x64,
            liquidity64x64
        );
    }

    /**
     * @inheritdoc IPoolSettings
     */
    function setFeeApy64x64(int128 feeApy64x64) external onlyProtocolOwner {
        PoolStorage.layout().feeApy64x64 = feeApy64x64;
    }
}
