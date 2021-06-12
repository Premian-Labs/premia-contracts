// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from '@solidstate/contracts/token/ERC20/ERC20.sol';
import {ERC20MetadataStorage} from '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';
import {Ownable, OwnableStorage} from '@solidstate/contracts/access/Ownable.sol';
import {EnumerableSet} from '@solidstate/contracts/utils/EnumerableSet.sol';

import {TradingCompetitionERC20} from './TradingCompetitionERC20.sol';

contract TradingCompetitionFactory is Ownable {
    event TokenDeployed(address addr, string symbol);

    using EnumerableSet for EnumerableSet.AddressSet;

    // Addresses with minting rights
    EnumerableSet.AddressSet private _minters;

    // Whitelisted addresses who can receive / send tokens
    EnumerableSet.AddressSet private _whitelisted;

    constructor () {
        OwnableStorage.layout().owner = msg.sender;
    }

    function deployToken(string memory symbol) public {
        TradingCompetitionERC20 token = new TradingCompetitionERC20(symbol);
        emit TokenDeployed(address(token), symbol);
    }

    //

    function isMinter(address _user) external view returns(bool) {
        return _minters.contains(_user);
    }

    function isWhitelisted(address _from, address _to) external view returns(bool) {
        if (_from == address (0) || _to == address(0)) return true;
        if (_whitelisted.contains(_from) || _whitelisted.contains(_to)) return true;

        return false;
    }

    //

    function addMinters(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _minters.add(_addr[i]);
        }
    }

    function removeMinters(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _minters.remove(_addr[i]);
        }
    }

    function getMinters() external view returns(address[] memory) {
        uint256 length = _minters.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _minters.at(i);
        }

        return result;
    }

    //

    function addWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.add(_addr[i]);
        }
    }

    function removeWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.remove(_addr[i]);
        }
    }

    function getWhitelisted() external view returns(address[] memory) {
        uint256 length = _whitelisted.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelisted.at(i);
        }

        return result;
    }
}
