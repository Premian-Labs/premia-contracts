// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Diamond} from "@solidstate/contracts/proxy/diamond/Diamond.sol";

import {ProxyManagerOldStorage} from "./ProxyManagerOldStorage.sol";

/**
 * @title Premia core contract
 * @dev based on the EIP2535 Diamond standard
 */
contract PremiaOld is Diamond {
    constructor(address _optionImplementation, address _marketImplementation) {
        ProxyManagerOldStorage.Layout storage l = ProxyManagerOldStorage
        .layout();
        l.optionImplementation = _optionImplementation;
        l.marketImplementation = _marketImplementation;
    }
}
