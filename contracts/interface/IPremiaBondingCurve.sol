// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IPremiaBondingCurveUpgrade} from "./IPremiaBondingCurveUpgrade.sol";

interface IPremiaBondingCurve {
    function startUpgrade(IPremiaBondingCurveUpgrade _newContract) external;

    function doUpgrade() external;
}
