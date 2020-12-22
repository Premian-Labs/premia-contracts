// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

interface IPremiaReferral {
    function trySetReferrer(address _referred, address _potentialReferrer) external returns(address);
}