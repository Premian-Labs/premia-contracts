// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";

/// @author Premia
/// @title The Premia token
contract PremiaErc20 is SolidStateERC20 {
    constructor() {
        _setName("Premia");
        _setSymbol("PREMIA");
        _setDecimals(18);

        _mint(msg.sender, 1e26);
        // 100m
    }
}
