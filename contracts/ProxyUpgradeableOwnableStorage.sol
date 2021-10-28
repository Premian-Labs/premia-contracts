// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.finance

pragma solidity ^0.8.0;

library ProxyUpgradeableOwnableStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.ProxyUpgradeableOwnable");

    struct Layout {
        address implementation;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
