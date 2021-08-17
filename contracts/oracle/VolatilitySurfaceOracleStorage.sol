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

    function parseVolatilitySurfaceCoefficients(bytes32 input)
        internal
        view
        returns (int256[] memory coefficients)
    {
        coefficients = new int256[](10);

        // Value to add to negative numbers to cast them to int256
        int256 toAdd = (int256(-1) >> 25) << 25;

        assembly {
            let i := 0
            // Value equal to -1
            let mid := shl(24, 1)

            for {

            } lt(i, 10) {

            } {
                let offset := sub(225, mul(25, i))
                let coeff := shr(
                    offset,
                    sub(
                        input,
                        shl(add(offset, 25), shr(add(offset, 25), input))
                    )
                )

                // Check if value is a negative number and needs casting
                if or(eq(coeff, mid), gt(coeff, mid)) {
                    coeff := add(coeff, toAdd)
                }

                // Store result in the coefficients array
                mstore(add(coefficients, add(0x20, mul(0x20, i))), coeff)

                i := add(i, 1)
            }
        }
    }

    function formatVolatilitySurfaceCoefficients(int256[10] memory coefficients)
        internal
        view
        returns (bytes32 result)
    {
        assembly {
            let i := 0

            for {

            } lt(i, 10) {

            } {
                let offset := sub(225, mul(25, i))
                let coeff := mload(add(coefficients, mul(0x20, i)))

                result := add(
                    result,
                    shl(offset, sub(coeff, shl(25, shr(25, coeff))))
                )

                i := add(i, 1)
            }
        }
    }
}
