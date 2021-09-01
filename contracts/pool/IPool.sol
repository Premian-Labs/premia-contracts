// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC1155} from "@solidstate/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";
import {IMulticall} from "@solidstate/contracts/utils/IMulticall.sol";

import {IPoolBase} from "./IPoolBase.sol";
import {IPoolEvents} from "./IPoolEvents.sol";
import {IPoolExercise} from "./IPoolExercise.sol";
import {IPoolIO} from "./IPoolIO.sol";
import {IPoolView} from "./IPoolView.sol";
import {IPoolWrite} from "./IPoolWrite.sol";

interface IPool is
    IERC1155,
    IERC1155Enumerable,
    IMulticall,
    IPoolBase,
    IPoolEvents,
    IPoolExercise,
    IPoolIO,
    IPoolView,
    IPoolWrite
{}
