// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ERC20MetadataInternal} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataInternal.sol";

import {ProxyUpgradeableOwnable} from "../ProxyUpgradeableOwnable.sol";

contract PremiaStakingProxy is ProxyUpgradeableOwnable, ERC20MetadataInternal {
    constructor(
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        _setName("Staked Premia");
        _setSymbol("xPREMIA");
        _setDecimals(18);
    }
}
