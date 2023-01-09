// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";

contract ERC20Placeholder is SolidStateERC20 {
    constructor() {
        _setName("Placeholder");
        _setSymbol("PLACEHOLDER");
        _setDecimals(18);
    }
}
