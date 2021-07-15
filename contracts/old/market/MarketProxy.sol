// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from "@solidstate/contracts/access/OwnableStorage.sol";
import {ManagedProxy} from "@solidstate/contracts/proxy/managed/ManagedProxy.sol";

import {IProxyManagerOld} from "../core/IProxyManagerOld.sol";
import {MarketStorage} from "./MarketStorage.sol";
import {ManagedProxyWithManager, ManagerStorage} from "../manager/ManagedProxyWithManager.sol";

contract MarketProxy is ManagedProxyWithManager {
    using MarketStorage for MarketStorage.Layout;

    constructor(
        address _owner,
        address _feeCalculator,
        address _feeRecipient
    ) ManagedProxy(IProxyManagerOld.getMarketImplementation.selector) {
        OwnableStorage.layout().owner = _owner;
        ManagerStorage.layout().manager = msg.sender;

        MarketStorage.Layout storage l = MarketStorage.layout();
        l.feeCalculator = _feeCalculator;
        l.feeRecipient = _feeRecipient;
        l.isDelayedWritingEnabled = true;
    }
}
