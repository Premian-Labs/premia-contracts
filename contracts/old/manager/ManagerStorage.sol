// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library ManagerStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256(
        'premia.contracts.storage.Manager'
    );

    struct Layout {
        address manager;
    }

    function layout () internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly { l.slot := slot }
    }

    function setManager (
        Layout storage l,
        address manager
    ) internal {
        l.manager = manager;
    }
}
