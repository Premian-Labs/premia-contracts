// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableStorage.sol';

import '../core/IProxyManager.sol';
import './MarketStorage.sol';
import '../manager/ManagedProxyWithManager.sol';

contract MarketProxy is ManagedProxyWithManager {
    using MarketStorage for MarketStorage.Layout;

    constructor(address _owner, address _feeCalculator, address _feeRecipient) ManagedProxy(IProxyManager.getMarketImplementation.selector) {
        OwnableStorage.layout().owner = _owner;
        ManagerStorage.layout().manager = msg.sender;

        MarketStorage.Layout storage l = MarketStorage.layout();
        l.feeCalculator = _feeCalculator;
        l.feeRecipient = _feeRecipient;
        l.isDelayedWritingEnabled = true;
    }
}
