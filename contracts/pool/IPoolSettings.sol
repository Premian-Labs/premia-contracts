// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPoolSettings {
    function setPoolCaps(uint256 basePoolCap, uint256 underlyingPoolCap)
        external;
}
