// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPoolControllerChild {
    function upgradeController(address _newController) external;
}
