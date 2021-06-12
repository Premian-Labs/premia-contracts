// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITradingCompetitionFactory {
    function isMinter(address _user) external returns(bool);
    function isWhitelisted(address _from, address _to) external returns(bool);
}
