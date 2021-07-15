// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from "@solidstate/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@solidstate/contracts/token/ERC20/ERC20Permit.sol";
import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol";

/// @author Premia
/// @title The Premia token
contract PremiaErc20 is ERC20, ERC20Permit {
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
