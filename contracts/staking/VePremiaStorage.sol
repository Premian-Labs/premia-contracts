// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

library VePremiaStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.staking.VePremia");

    struct Vote {
        uint256 amount;
        address poolAddress;
        bool isCallPool;
    }

    struct Layout {
        uint256 totalVotingPower;
        mapping(address => Vote[]) userVotes;
        // Pool address -> Is Call Pool -> Vote amount
        mapping(address => mapping(bool => uint256)) votes;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
