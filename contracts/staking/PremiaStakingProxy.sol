// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ProxyUpgradeableOwnable} from "../ProxyUpgradeableOwnable.sol";
import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";

contract PremiaStakingProxy is ProxyUpgradeableOwnable {
    using ERC20MetadataStorage for ERC20MetadataStorage.Layout;

    constructor(
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();
        l.name = "Staked Premia";
        l.symbol = "xPREMIA";
        l.decimals = 18;
    }
}
