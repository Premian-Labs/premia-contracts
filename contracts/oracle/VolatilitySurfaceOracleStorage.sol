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

    function parseVolatilitySurface(bytes32 input)
        internal
        view
        returns (int256[] memory coefficients)
    {
        coefficients = new int256[](10);

        // ToDo : Assembly loop
        assembly {
            mstore(add(coefficients, 0x20), shr(225, input))
            mstore(
                add(coefficients, 0x40),
                shr(200, sub(input, shl(225, shr(225, input))))
            )
            mstore(
                add(coefficients, 0x60),
                shr(175, sub(input, shl(200, shr(200, input))))
            )
            mstore(
                add(coefficients, 0x80),
                shr(150, sub(input, shl(175, shr(175, input))))
            )
            mstore(
                add(coefficients, 0xA0),
                shr(125, sub(input, shl(150, shr(150, input))))
            )
            mstore(
                add(coefficients, 0xC0),
                shr(100, sub(input, shl(125, shr(125, input))))
            )
            mstore(
                add(coefficients, 0xE0),
                shr(75, sub(input, shl(100, shr(100, input))))
            )
            mstore(
                add(coefficients, 0x100),
                shr(50, sub(input, shl(75, shr(75, input))))
            )
            mstore(
                add(coefficients, 0x120),
                shr(25, sub(input, shl(50, shr(50, input))))
            )
            mstore(
                add(coefficients, 0x140),
                sub(input, shl(25, shr(25, input)))
            )
        }

        // ToDo : Convert to assembly
        int256 toAdd = (int256(-1) >> 25) << 25;
        uint256 i = 0;

        while (i < 10) {
            if (uint256(coefficients[i]) >= uint256(1) << 24) {
                coefficients[i] += toAdd;
            }

            i++;
        }

        return coefficients;
    }

    function formatVolatilitySurface(int256[10] memory coefficients)
        internal
        view
        returns (bytes32)
    {
        uint256 result = 0;

        uint256 i = 0;
        while (i < 10) {
            result += uint256(coefficients[i] << (225 - (i * 25)));
            i++;
        }

        return bytes32(result);
    }
}
