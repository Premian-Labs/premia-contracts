// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {IPoolInternal} from "./IPoolInternal.sol";
import {IPoolBase} from "./IPoolBase.sol";
import {IPoolEvents} from "./IPoolEvents.sol";
import {IPoolExercise} from "./IPoolExercise.sol";
import {IPoolIO} from "./IPoolIO.sol";
import {IPoolSell} from "./IPoolSell.sol";
import {IPoolSettings} from "./IPoolSettings.sol";
import {IPoolView} from "./IPoolView.sol";
import {IPoolWrite} from "./IPoolWrite.sol";

interface IPool is
    IPoolInternal,
    IPoolBase,
    IPoolEvents,
    IPoolExercise,
    IPoolIO,
    IPoolSell,
    IPoolSettings,
    IPoolView,
    IPoolWrite
{}
