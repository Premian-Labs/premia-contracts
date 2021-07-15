// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {SafeOwnable, OwnableStorage} from "@solidstate/contracts/access/SafeOwnable.sol";
import {ProxyUpgradeableOwnableStorage} from "./ProxyUpgradeableOwnableStorage.sol";

contract ProxyUpgradeableOwnable is Proxy, SafeOwnable {
    using ProxyUpgradeableOwnableStorage for ProxyUpgradeableOwnableStorage.Layout;
    using OwnableStorage for OwnableStorage.Layout;

    constructor(address implementation) {
        OwnableStorage.layout().setOwner(msg.sender);
        ProxyUpgradeableOwnableStorage.layout().implementation = implementation;
    }

    receive() external payable {}

    /**
     * @inheritdoc Proxy
     */
    function _getImplementation() internal view override returns (address) {
        return ProxyUpgradeableOwnableStorage.layout().implementation;
    }

    /**
     * @notice get address of implementation contract
     * @return implementation address
     */
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @notice set address of implementation contract
     * @param implementation address of the new implementation
     */
    function setImplementation(address implementation) external onlyOwner {
        ProxyUpgradeableOwnableStorage.layout().implementation = implementation;
    }
}
