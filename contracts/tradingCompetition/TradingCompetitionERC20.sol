// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from '@solidstate/contracts/token/ERC20/ERC20.sol';
import {ERC20MetadataStorage} from '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';
import {ITradingCompetitionFactory} from './ITradingCompetitionFactory.sol';

contract TradingCompetitionERC20 is ERC20 {
    ITradingCompetitionFactory public immutable factory;

    constructor (string memory symbol) {
        factory = ITradingCompetitionFactory(msg.sender);
        ERC20MetadataStorage.layout().symbol = symbol;
        ERC20MetadataStorage.layout().decimals = 18;
    }

    modifier isMinter() {
        require(factory.isMinter(msg.sender), 'Not minter');
        _;
    }

    function mint(address _account, uint256 _amount) public isMinter {
        _mint(_account, _amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256) override view internal {
        require(factory.isWhitelisted(from, to), 'Not whitelisted');
    }
}
