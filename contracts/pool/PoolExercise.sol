// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC1155BaseStorage} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseStorage.sol";

import {PoolInternal} from "./PoolInternal.sol";
import {IPoolExercise} from "./IPoolExercise.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolExercise is IPoolExercise, PoolInternal {
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
     * @notice exercise call option on behalf of holder
     * @param holder owner of long option tokens to exercise
     * @param longTokenId long option token id
     * @param contractSize quantity of tokens to exercise
     */
    function exerciseFrom(
        address holder,
        uint256 longTokenId,
        uint256 contractSize
    ) external override {
        if (msg.sender != holder) {
            require(
                ERC1155BaseStorage.layout().operatorApprovals[holder][
                    msg.sender
                ],
                "not approved"
            );
        }

        _exercise(holder, longTokenId, contractSize);
    }

    /**
     * @notice process expired option, freeing liquidity and distributing profits
     * @param longTokenId long option token id
     * @param contractSize quantity of tokens to process
     */
    function processExpired(uint256 longTokenId, uint256 contractSize)
        external
        override
    {
        _exercise(address(0), longTokenId, contractSize);
    }
}
