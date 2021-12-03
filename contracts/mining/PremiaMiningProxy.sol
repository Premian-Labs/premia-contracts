// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ProxyUpgradeableOwnable} from "../ProxyUpgradeableOwnable.sol";
import {PremiaMiningStorage} from "./PremiaMiningStorage.sol";

contract PremiaMiningProxy is ProxyUpgradeableOwnable {
    constructor(address implementation, uint256 premiaPerYear)
        ProxyUpgradeableOwnable(implementation)
    {
        PremiaMiningStorage.layout().premiaPerYear = premiaPerYear;
    }
}
