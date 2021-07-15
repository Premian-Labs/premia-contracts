// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITradingCompetitionFactory {
    function isMinter(address _user) external view returns (bool);

    function isWhitelisted(address _from, address _to)
        external
        view
        returns (bool);
}
