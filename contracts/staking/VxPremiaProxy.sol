// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ERC20MetadataInternal} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataInternal.sol";

import {ProxyUpgradeableOwnable} from "../ProxyUpgradeableOwnable.sol";

contract VxPremiaProxy is ProxyUpgradeableOwnable, ERC20MetadataInternal {
    constructor(
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        _setName("vxPremia");
        _setSymbol("vxPREMIA");
        _setDecimals(18);
    }
}
