// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { EnumerableSet } from '@solidstate/contracts/utils/EnumerableSet.sol';

library PremiaMakerStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256(
        'premia.contracts.storage.PremiaMaker'
    );

    struct Layout {
        // UniswapRouter contracts which can be used to swap tokens
        EnumerableSet.AddressSet whitelistedRouters;

        // Set a custom swap path for a token
        mapping(address=>address[]) customPath;
    }

    function layout () internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly { l.slot := slot }
    }
}
