// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Diamond} from "@solidstate/contracts/proxy/diamond/Diamond.sol";
import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";

contract PremiaStakingProxy is Diamond {
    using ERC20MetadataStorage for ERC20MetadataStorage.Layout;

    constructor() {
        ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();
        l.setName("PremiaStaking");
        l.setSymbol("xPremia");
        l.setDecimals(18);
    }
}
