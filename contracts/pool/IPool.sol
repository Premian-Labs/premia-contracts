// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolBase} from "./IPoolBase.sol";
import {IPoolEvents} from "./IPoolEvents.sol";
import {IPoolExercise} from "./IPoolExercise.sol";
import {IPoolIO} from "./IPoolIO.sol";
import {IPoolView} from "./IPoolView.sol";
import {IPoolWrite} from "./IPoolWrite.sol";

interface IPool is
    IPoolBase,
    IPoolEvents,
    IPoolExercise,
    IPoolIO,
    IPoolView,
    IPoolWrite
{}
