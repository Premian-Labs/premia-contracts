// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {ProxyUpgradeableOwnable} from "../ProxyUpgradeableOwnable.sol";

import {ChainlinkWrapperStorage} from "./ChainlinkWrapperStorage.sol";

contract ChainlinkWrapperProxy is ERC165BaseInternal, ProxyUpgradeableOwnable {
    using ChainlinkWrapperStorage for ChainlinkWrapperStorage.Layout;

    /// @notice Thrown when cardinality per minute has not been set
    error ChainlinkWrapperProxy__CardinalityPerMinuteNotSet();

    /// @notice Thrown when period has not been set
    error ChainlinkWrapperProxy__PeriodNotSet();

    constructor(
        uint8 cardinalityPerMinute,
        uint32 period,
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        if (cardinalityPerMinute == 0)
            revert ChainlinkWrapperProxy__CardinalityPerMinuteNotSet();

        if (period == 0) revert ChainlinkWrapperProxy__PeriodNotSet();

        ChainlinkWrapperStorage.Layout storage l = ChainlinkWrapperStorage
            .layout();

        l.targetCardinality = uint16((period * cardinalityPerMinute) / 60) + 1;

        l.cardinalityPerMinute = cardinalityPerMinute;
        l.period = period;

        l.feeTiers.push(100);
        l.feeTiers.push(500);
        l.feeTiers.push(3_000);
        l.feeTiers.push(10_000);

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(Multicall).interfaceId, true);
    }
}
