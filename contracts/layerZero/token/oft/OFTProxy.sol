// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC165BaseStorage} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseStorage.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ProxyUpgradeableOwnable} from "../../../ProxyUpgradeableOwnable.sol";
import {IOFT} from "./IOFT.sol";
import {IOFTCore} from "./IOFTCore.sol";

contract OFTProxy is ProxyUpgradeableOwnable {
    using ERC165BaseStorage for ERC165BaseStorage.Layout;

    constructor(
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        {
            ERC165BaseStorage.Layout storage l = ERC165BaseStorage.layout();
            l.supportedInterfaces[type(IERC165).interfaceId] = true;
            l.supportedInterfaces[type(IERC20).interfaceId] = true;
            l.supportedInterfaces[type(IOFTCore).interfaceId] = true;
            l.supportedInterfaces[type(IOFT).interfaceId] = true;
        }
    }
}
