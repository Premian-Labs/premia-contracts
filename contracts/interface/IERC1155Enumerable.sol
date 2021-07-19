// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// ToDo : Remove once added in solidstate
interface IERC1155Enumerable {
    function totalSupply(uint256 id) external view returns (uint256);

    function totalHolders(uint256 id) external view returns (uint256);

    function accountsByToken(uint256 id)
        external
        view
        returns (address[] memory);

    function tokensByAccount(address account)
        external
        view
        returns (uint256[] memory);
}
