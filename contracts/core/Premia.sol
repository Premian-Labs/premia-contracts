// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/proxy/diamond/Diamond.sol';

import './ProxyManagerStorage.sol';

/**
 * @title Premia core contract
 * @dev based on the EIP2535 Diamond standard
 */
contract Premia is Diamond {

    constructor (address _optionImplementation, address _marketImplementation) {
        ProxyManagerStorage.Layout storage l = ProxyManagerStorage.layout();
        l.optionImplementation = _optionImplementation;
        l.marketImplementation = _marketImplementation;
    }
}
