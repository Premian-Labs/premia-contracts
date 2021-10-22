// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";

library VolatilitySurfaceOracleStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.VolatilitySurfaceOracle");

    uint256 internal constant COEFF_BITS = 51;
    uint256 internal constant COEFF_BITS_MINUS_ONE = 50;
    uint256 internal constant COEFF_AMOUNT = 5;
    // START_BIT = COEFF_BITS * (COEFF_AMOUNT - 1)
    uint256 internal constant START_BIT = 204;

    struct Update {
        uint256 updatedAt;
        bytes32 coefficients;
    }

    struct Layout {
        // Base token -> Underlying token -> Update
        mapping(address => mapping(address => Update)) volatilitySurfaces;
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
        pure
        returns (int256[] memory coefficients)
    {
        coefficients = new int256[](COEFF_AMOUNT);

        // Value to add to negative numbers to cast them to int256
        int256 toAdd = (int256(-1) >> COEFF_BITS) << COEFF_BITS;

        assembly {
            let i := 0
            // Value equal to -1
            let mid := shl(COEFF_BITS_MINUS_ONE, 1)

            for {

            } lt(i, COEFF_AMOUNT) {

            } {
                let offset := sub(START_BIT, mul(COEFF_BITS, i))
                let coeff := shr(
                    offset,
                    sub(
                        input,
                        shl(
                            add(offset, COEFF_BITS),
                            shr(add(offset, COEFF_BITS), input)
                        )
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

    function formatVolatilitySurfaceCoefficients(int256[5] memory coefficients)
        internal
        pure
        returns (bytes32 result)
    {
        for (uint256 i = 0; i < COEFF_AMOUNT; i++) {
            int256 max = int256(1 << COEFF_BITS_MINUS_ONE);
            require(
                coefficients[i] < max && coefficients[i] > -max,
                "Out of bounds"
            );
        }

        assembly {
            let i := 0

            for {

            } lt(i, COEFF_AMOUNT) {

            } {
                let offset := sub(START_BIT, mul(COEFF_BITS, i))
                let coeff := mload(add(coefficients, mul(0x20, i)))

                result := add(
                    result,
                    shl(
                        offset,
                        sub(coeff, shl(COEFF_BITS, shr(COEFF_BITS, coeff)))
                    )
                )

                i := add(i, 1)
            }
        }
    }
}
