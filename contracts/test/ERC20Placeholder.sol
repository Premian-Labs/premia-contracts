// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ERC20} from "@solidstate/contracts/token/ERC20/ERC20.sol";
import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";

contract ERC20Placeholder is ERC20 {
    using ERC20MetadataStorage for ERC20MetadataStorage.Layout;

    constructor() {
        ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();

        l.setName("Placeholder");
        l.setSymbol("PLACEHOLDER");
        l.setDecimals(18);
    }
}
