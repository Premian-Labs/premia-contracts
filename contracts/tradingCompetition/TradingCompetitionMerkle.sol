// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from https://github.com/Uniswap/merkle-distributor

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import {ITradingCompetitionERC20} from './ITradingCompetitionERC20.sol';

interface ITradingCompetitionMerkle {
    // Returns the merkle root of the merkle tree containing account balances available to claim.
    function merkleRoots(uint256 airdropId) external view returns (bytes32);

    // Returns true if the index has been marked claimed.
    function isClaimed(uint256 airdropId, uint256 index) external view returns (bool);

    // Claim the given amount of the tokens to the given address. Reverts if the inputs are invalid.
    function claim(uint256 airdropId, uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external;

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(
        uint256 airdropId,
        uint256 index,
        address account,
        uint256 amount
    );
}

contract TradingCompetitionMerkle is ITradingCompetitionMerkle, Ownable {
    IERC20[] public tokens;
    // tokenAmount = amount * weight / _inverseBasisPoint
    // Example :
    // -> 1e4 = amount
    // -> 1e5 = amount * 10
    mapping(address => uint256) weights;

    // Mapping of airdropIds to merkle roots
    mapping(uint256 => bytes32) public override merkleRoots;

    // Mapping of airdropIds to packed array of booleans
    mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMaps;

    uint256 private constant _inverseBasisPoint = 1e4;

    constructor(IERC20[] memory _tokens, uint256[] memory _weights) {
        tokens = _tokens;

        for (uint256 i=0; i < _tokens.length; i++) {
            require(weights[address(_tokens[i])] == 0, 'Token duplicate');
            weights[address(_tokens[i])] = _weights[i];
        }
    }

    function addMerkleRoot(uint256 airdropId, bytes32 merkleRoot) public onlyOwner {
        merkleRoots[airdropId] = merkleRoot;
    }

    function isClaimed(uint256 airdropId, uint256 index) public override view returns (bool) {
        mapping(uint256 => uint256) storage claimed = claimedBitMaps[airdropId];

        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimed[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);

        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 airdropId, uint256 index) private {
        mapping(uint256 => uint256) storage claimed = claimedBitMaps[airdropId];

        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;

        claimed[claimedWordIndex] =
        claimed[claimedWordIndex] |
        (1 << claimedBitIndex);
    }

    function claim(uint256 airdropId, uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external override {
        require(!isClaimed(airdropId, index), 'Already claimed');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));

        require(MerkleProof.verify(merkleProof, merkleRoots[airdropId], node), 'Invalid proof');

        // Mark it claimed and send the tokens
        _setClaimed(airdropId, index);

        for (uint256 i=0; i < tokens.length; i++) {
            ITradingCompetitionERC20(address(tokens[i])).mint(account, amount * weights[address(tokens[i])] / _inverseBasisPoint);
        }

        emit Claimed(airdropId, index, account, amount);
    }
}
