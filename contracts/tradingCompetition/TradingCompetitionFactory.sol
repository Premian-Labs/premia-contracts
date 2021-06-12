// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from '@solidstate/contracts/token/ERC20/ERC20.sol';
import {ERC20MetadataStorage} from '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';
import {Ownable, OwnableStorage} from '@solidstate/contracts/access/Ownable.sol';

import {TradingCompetitionERC20} from './TradingCompetitionERC20.sol';

contract TradingCompetitionFactory is Ownable {
    event TokenDeployed(address addr, string symbol);

    constructor () {
        OwnableStorage.layout().owner = msg.sender;
    }

    function deployToken(string memory symbol) public {
        TradingCompetitionERC20 token = new TradingCompetitionERC20(symbol);
        emit TokenDeployed(address(token), symbol);
    }

    function isMinter(address _user) external returns(bool) {
        // ToDo : Implement
        return true;
    }

    function isWhitelisted(address _user) external returns(bool) {
        // ToDo : Implement
        return true;
    }
}
