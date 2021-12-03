// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {IERC1155} from "@solidstate/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";
import {IMulticall} from "@solidstate/contracts/utils/IMulticall.sol";

/**
 * @notice Base Pool interface, including ERC1155 functions
 */
interface IPoolBase is IERC1155, IERC1155Enumerable, IMulticall {
    /**
     * @notice get token collection name
     * @return collection name
     */
    function name() external view returns (string memory);
}
