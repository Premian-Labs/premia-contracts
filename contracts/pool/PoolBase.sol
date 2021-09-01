// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC165} from "@solidstate/contracts/introspection/ERC165.sol";
import {ERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {PoolInternal} from "./PoolInternal.sol";

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract PoolBase is PoolInternal, ERC1155Enumerable, ERC165, Multicall {
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

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(PoolInternal, ERC1155Enumerable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
