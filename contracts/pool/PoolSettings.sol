// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC173} from "@solidstate/contracts/access/IERC173.sol";
import {OwnableStorage} from "@solidstate/contracts/access/OwnableStorage.sol";

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

    modifier onlyOwner() {
        require(
            msg.sender == IERC173(OwnableStorage.layout().owner).owner(),
            "Not owner"
        );
        _;
    }

    function setPoolCaps(uint256 basePoolCap, uint256 underlyingPoolCap)
        external
        override
        onlyOwner
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        l.basePoolCap = basePoolCap;
        l.underlyingPoolCap = underlyingPoolCap;
    }
}
