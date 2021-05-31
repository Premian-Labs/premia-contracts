// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@solidstate/contracts/proxy/managed/ManagedProxy.sol';
import './ManagerStorage.sol';

/**
 * @title Proxy with implementation controlled by manager
 */
abstract contract ManagedProxyWithManager is ManagedProxy {
    /**
     * @inheritdoc ManagedProxy
     */
    function _getManager () override internal view returns (address) {
        return ManagerStorage.layout().manager;
    }
}
