// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ProxyUpgradeableOwnable} from "../ProxyUpgradeableOwnable.sol";
import {PoolMiningStorage} from "./PoolMiningStorage.sol";

contract PoolMiningProxy is ProxyUpgradeableOwnable {
    constructor(address implementation, uint256 premiaPerBlock)
        ProxyUpgradeableOwnable(implementation)
    {
        PoolMiningStorage.layout().premiaPerBlock = premiaPerBlock;
    }
}
