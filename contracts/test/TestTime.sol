// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

// Used to mock timestamp for unit test purpose
contract TestTime {
    uint256 public timestamp;

    function setTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }
}