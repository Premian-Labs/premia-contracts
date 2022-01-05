// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";

library VolatilitySurfaceOracleStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.VolatilitySurfaceOracle");

    uint256 internal constant PARAM_BITS = 51;
    uint256 internal constant PARAM_BITS_MINUS_ONE = 50;
    uint256 internal constant PARAM_AMOUNT = 5;
    // START_BIT = PARAM_BITS * (PARAM_AMOUNT - 1)
    uint256 internal constant START_BIT = 204;

    struct Update {
        uint256 updatedAt;
        bytes32 params;
    }

    struct Layout {
        // Base token -> Underlying token -> Update
        mapping(address => mapping(address => Update)) parameters;
        // Relayer addresses which can be trusted to provide accurate option trades
        EnumerableSet.AddressSet whitelistedRelayers;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function getParams(
        Layout storage l,
        address base,
        address underlying
    ) internal view returns (bytes32) {
        return l.parameters[base][underlying].params;
    }

    function parseParams(bytes32 input)
        internal
        pure
        returns (int256[] memory params)
    {
        params = new int256[](PARAM_AMOUNT);

        // Value to add to negative numbers to cast them to int256
        int256 toAdd = (int256(-1) >> PARAM_BITS) << PARAM_BITS;

        assembly {
            let i := 0
            // Value equal to -1

            let mid := shl(PARAM_BITS_MINUS_ONE, 1)

            for {

            } lt(i, PARAM_AMOUNT) {

            } {
                let offset := sub(START_BIT, mul(PARAM_BITS, i))
                let param := shr(
                    offset,
                    sub(
                        input,
                        shl(
                            add(offset, PARAM_BITS),
                            shr(add(offset, PARAM_BITS), input)
                        )
                    )
                )

                // Check if value is a negative number and needs casting
                if or(eq(param, mid), gt(param, mid)) {
                    param := add(param, toAdd)
                }

                // Store result in the params array
                mstore(add(params, add(0x20, mul(0x20, i))), param)

                i := add(i, 1)
            }
        }
    }

    function formatParams(int256[5] memory params)
        internal
        pure
        returns (bytes32 result)
    {
        int256 max = int256(1 << PARAM_BITS_MINUS_ONE);

        unchecked {
            for (uint256 i = 0; i < PARAM_AMOUNT; i++) {
                require(params[i] < max && params[i] > -max, "Out of bounds");
            }
        }

        assembly {
            let i := 0

            for {

            } lt(i, PARAM_AMOUNT) {

            } {
                let offset := sub(START_BIT, mul(PARAM_BITS, i))
                let param := mload(add(params, mul(0x20, i)))

                result := add(
                    result,
                    shl(
                        offset,
                        sub(param, shl(PARAM_BITS, shr(PARAM_BITS, param)))
                    )
                )

                i := add(i, 1)
            }
        }
    }
}
