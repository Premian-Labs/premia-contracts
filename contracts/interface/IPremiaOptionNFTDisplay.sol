// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPremiaOptionNFTDisplay {
    function tokenURI(address _pool, uint256 _tokenId)
        external
        view
        returns (string memory);
}
