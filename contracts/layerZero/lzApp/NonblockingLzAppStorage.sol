// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library NonblockingLzAppStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.NonblockingLzApp");

    struct Layout {
        mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) failedMessages;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
