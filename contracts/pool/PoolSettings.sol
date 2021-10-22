// SPDX-License-Identifier: UNLICENSED

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

    address internal immutable MULTISIG;

    constructor(
        address multisig,
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
        MULTISIG = multisig;
    }

    modifier onlyMultisig() {
        require(msg.sender == MULTISIG, "Not multisig");
        _;
    }

    function setPoolCaps(uint256 basePoolCap, uint256 underlyingPoolCap)
        external
        override
        onlyMultisig
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        l.basePoolCap = basePoolCap;
        l.underlyingPoolCap = underlyingPoolCap;
    }
}
