// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";

import {ProxyUpgradeableOwnable} from "../ProxyUpgradeableOwnable.sol";

contract VxPremiaProxy is ProxyUpgradeableOwnable {
    using ERC20MetadataStorage for ERC20MetadataStorage.Layout;

    constructor(address implementation)
        ProxyUpgradeableOwnable(implementation)
    {
        ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();
        l.setName("vxPREMIA");
        l.setSymbol("vxPREMIA");
        l.setDecimals(18);
    }
}
