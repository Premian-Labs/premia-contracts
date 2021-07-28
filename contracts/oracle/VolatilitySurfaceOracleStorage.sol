// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";

library VolatilitySurfaceOracleStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.VolatilitySurfaceOracle");

    struct Layout {
        // Base token -> Underlying token -> Is Call vs. Put -> Polynomial coefficients
        mapping(address => mapping(address => mapping(bool => int128[]))) volatilitySurfaces;
        // Base token -> Underlying token -> Is Call vs. Put -> Last update timestamp
        mapping(address => mapping(address => mapping(bool => uint256))) lastUpdateTimestamps;
        // Relayer addresses which can be trusted to provide accurate option trades
        EnumerableSet.AddressSet whitelistedRelayers;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
