// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ProxyUpgradeableOwnable} from "../ProxyUpgradeableOwnable.sol";

contract VolatilitySurfaceOracleProxy is ProxyUpgradeableOwnable {
    constructor(address implementation)
        ProxyUpgradeableOwnable(implementation)
    {}
}
