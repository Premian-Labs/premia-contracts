// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from "@solidstate/contracts/access/OwnableStorage.sol";
import {Diamond} from "@solidstate/contracts/proxy/diamond/Diamond.sol";

/**
 * @title Premia core contract
 * @dev based on the EIP2535 Diamond standard
 */
contract Premia is Diamond {
    constructor() {
        OwnableStorage.layout().owner = msg.sender;
    }
}
