// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.finance

pragma solidity ^0.8.0;

import {PoolStorage} from "./PoolStorage.sol";

import {IPoolSettings} from "./IPoolSettings.sol";
import {PoolInternal} from "./PoolInternal.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolSettings is IPoolSettings, PoolInternal {
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

    function setPoolCaps(uint256 basePoolCap, uint256 underlyingPoolCap)
        external
        override
        onlyProtocolOwner
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        l.basePoolCap = basePoolCap;
        l.underlyingPoolCap = underlyingPoolCap;
    }

    function setMinimumAmounts(uint256 baseMinimum, uint256 underlyingMinimum)
        external
        override
        onlyProtocolOwner
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        l.baseMinimum = baseMinimum;
        l.underlyingMinimum = underlyingMinimum;
    }

    function setSteepness64x64(int128 steepness64x64)
        external
        override
        onlyProtocolOwner
    {
        PoolStorage.layout().steepness64x64 = steepness64x64;
        emit UpdateSteepness(steepness64x64);
    }

    function setCLevel64x64(int128 cLevel64x64, bool isCallPool)
        external
        override
        onlyProtocolOwner
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        int128 liquidity64x64 = l.totalFreeLiquiditySupply64x64(isCallPool);

        if (isCallPool) {
            l.cLevelUnderlying64x64 = cLevel64x64;
            l.cLevelUnderlyingUpdatedAt = block.timestamp;
        } else {
            l.cLevelBase64x64 = cLevel64x64;
            l.cLevelBaseUpdatedAt = block.timestamp;
        }

        emit UpdateCLevel(
            isCallPool,
            cLevel64x64,
            liquidity64x64,
            liquidity64x64
        );
    }
}
