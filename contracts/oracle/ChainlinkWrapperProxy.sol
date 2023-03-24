// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {ProxyUpgradeableOwnable} from "../ProxyUpgradeableOwnable.sol";

import {ChainlinkWrapperStorage} from "./ChainlinkWrapperStorage.sol";

contract ChainlinkWrapperProxy is ERC165BaseInternal, ProxyUpgradeableOwnable {
    using ChainlinkWrapperStorage for ChainlinkWrapperStorage.Layout;

    constructor(
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        ChainlinkWrapperStorage.Layout storage l = ChainlinkWrapperStorage
            .layout();

        l.feeTiers.push(100);
        l.feeTiers.push(500);
        l.feeTiers.push(3_000);
        l.feeTiers.push(10_000);

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(Multicall).interfaceId, true);
    }
}
