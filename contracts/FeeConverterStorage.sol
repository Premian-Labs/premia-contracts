// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

library FeeConverterStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.FeeConverter");

    struct Layout {
        // Whether the address is authorized to call the convert function or not
        mapping(address => bool) isAuthorized;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
