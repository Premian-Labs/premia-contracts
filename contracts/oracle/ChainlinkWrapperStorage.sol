// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IChainlinkWrapperInternal} from "./IChainlinkWrapperInternal.sol";

library ChainlinkWrapperStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.ChainlinkWrapper");

    struct Layout {
        uint8 cardinalityPerMinute;
        uint16 targetCardinality;
        uint32 period;
        uint24[] feeTiers;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
