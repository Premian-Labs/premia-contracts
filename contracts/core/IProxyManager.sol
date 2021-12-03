// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IProxyManager {
    function getPoolList() external view returns (address[] memory);
}
