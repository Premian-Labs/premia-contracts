// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";

/// @author Premia
/// @title The Premia token
contract PremiaErc20 is SolidStateERC20 {
    using ERC20MetadataStorage for ERC20MetadataStorage.Layout;

    constructor() {
        ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();

        l.setName("Premia");
        l.setSymbol("PREMIA");
        l.setDecimals(18);

        _mint(msg.sender, 1e26);
        // 100m
    }
}
