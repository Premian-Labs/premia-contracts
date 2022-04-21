// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

library VePremiaStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.staking.VePremia");

    struct Vote {
        uint256 amount;
        uint256 chainId;
        address poolAddress;
        bool isCallPool;
    }

    struct Layout {
        uint256 totalVotingPower;
        mapping(address => Vote[]) userVotes;
        // ChainID -> Pool address -> Is Call Pool -> Vote amount
        mapping(uint256 => mapping(address => mapping(bool => uint256))) votes;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
