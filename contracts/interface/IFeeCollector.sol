// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IFeeCollector {
    function withdraw(address[] memory pools, address[] memory tokens) external;
}
