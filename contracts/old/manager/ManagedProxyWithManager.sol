// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ManagedProxy} from "@solidstate/contracts/proxy/managed/ManagedProxy.sol";
import {ManagerStorage} from "./ManagerStorage.sol";

/**
 * @title Proxy with implementation controlled by manager
 */
abstract contract ManagedProxyWithManager is ManagedProxy {
    /**
     * @inheritdoc ManagedProxy
     */
    function _getManager() internal view override returns (address) {
        return ManagerStorage.layout().manager;
    }
}
