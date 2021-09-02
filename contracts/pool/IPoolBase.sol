// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC1155} from "@solidstate/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";
import {IMulticall} from "@solidstate/contracts/utils/IMulticall.sol";

interface IPoolBase is IERC1155, IERC1155Enumerable, IMulticall {}
