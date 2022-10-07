// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library OFTCoreStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.OFTCore");

    struct Layout {
        bool useCustomAdapterParams;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
