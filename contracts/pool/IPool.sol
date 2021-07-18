// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolEvents} from "./IPoolEvents.sol";
import {IPoolExercise} from "./IPoolExercise.sol";
import {IPoolIO} from "./IPoolIO.sol";
import {IPoolView} from "./IPoolView.sol";
import {IPoolWrite} from "./IPoolWrite.sol";

import {IERC1155} from "@solidstate/contracts/token/ERC1155/IERC1155.sol";

// ToDo : Replace once added in solidstate
import {IERC1155Enumerable} from "../interface/IERC1155Enumerable.sol";

// import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/IERC1155Enumerable.sol";

interface IPool is
    IERC1155,
    IERC1155Enumerable,
    IPoolEvents,
    IPoolExercise,
    IPoolIO,
    IPoolView,
    IPoolWrite
{

}
