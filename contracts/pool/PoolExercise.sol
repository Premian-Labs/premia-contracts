// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

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
        address wrappedNativeToken,
        address premiaMining,
        address feeReceiver,
        address feeDiscountAddress,
        int128 feePremium64x64,
        address exchangeHelper
    )
        PoolInternal(
            ivolOracle,
            wrappedNativeToken,
            premiaMining,
            feeReceiver,
            feeDiscountAddress,
            feePremium64x64,
            exchangeHelper
        )
    {}

    /**
     * @inheritdoc IPoolExercise
     */
    function exerciseFrom(
        address holder,
        uint256 longTokenId,
        uint256 contractSize
    ) external {
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
     * @inheritdoc IPoolExercise
     */
    function processExpired(uint256 longTokenId, uint256 contractSize)
        external
    {
        _exercise(address(0), longTokenId, contractSize);
    }
}
