// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC165Storage} from "@solidstate/contracts/introspection/ERC165Storage.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ProxyUpgradeableOwnable} from "../../../ProxyUpgradeableOwnable.sol";
import {IOFT} from "./IOFT.sol";
import {IOFTCore} from "./IOFTCore.sol";

contract OFTProxy is ProxyUpgradeableOwnable {
    using ERC165Storage for ERC165Storage.Layout;

    constructor(address implementation)
        ProxyUpgradeableOwnable(implementation)
    {
        {
            ERC165Storage.Layout storage l = ERC165Storage.layout();
            l.setSupportedInterface(type(IERC165).interfaceId, true);
            l.setSupportedInterface(type(IERC20).interfaceId, true);
            l.setSupportedInterface(type(IOFTCore).interfaceId, true);
            l.setSupportedInterface(type(IOFT).interfaceId, true);
        }
    }
}
