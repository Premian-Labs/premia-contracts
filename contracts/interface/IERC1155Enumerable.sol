// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IERC1155Enumerable {
    function totalSupply(uint256 id) external view returns (uint256);
}
