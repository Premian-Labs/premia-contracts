// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from '@solidstate/contracts/token/ERC20/ERC20.sol';
import {ERC20MetadataStorage} from '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';
import {Ownable, OwnableStorage} from '@solidstate/contracts/access/Ownable.sol';
import {EnumerableSet} from '@solidstate/contracts/utils/EnumerableSet.sol';
import {AggregatorInterface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol';

import {TradingCompetitionERC20} from './TradingCompetitionERC20.sol';

contract TradingCompetitionFactory is Ownable {
    event TokenDeployed(address addr, address oracle, string symbol);

    using EnumerableSet for EnumerableSet.AddressSet;

    // Addresses with minting rights
    EnumerableSet.AddressSet private _minters;

    // Whitelisted addresses who can receive / send tokens
    EnumerableSet.AddressSet private _whitelisted;

    // token -> oracle
    mapping(address => address) public oracles;

    //

    event Swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    //

    constructor () {
        OwnableStorage.layout().owner = msg.sender;
    }

    //

    function deployToken(string memory _symbol, address _oracle) external returns(address) {
        TradingCompetitionERC20 token = new TradingCompetitionERC20(_symbol);
        oracles[address(token)] = _oracle;
        emit TokenDeployed(address(token), _oracle, _symbol);
        return address(token);
    }

    function setOracle(address _token, address _oracle) external onlyOwner {
        oracles[_token] = _oracle;
    }

    //

    // Swap functions

    function getAmountOut(address _tokenIn, address _tokenOut, uint256 _amountIn) public view returns(uint256) {
        uint256 tokenInPrice = uint256(AggregatorInterface(oracles[_tokenIn]).latestAnswer());
        uint256 tokenOutPrice = uint256(AggregatorInterface(oracles[_tokenOut]).latestAnswer());

        return (_amountIn * tokenInPrice / tokenOutPrice) * 99 / 100; // 1% fee burnt
    }

    function getAmountIn(address _tokenIn, address _tokenOut, uint256 _amountOut) public view returns(uint256) {
        uint256 tokenInPrice = uint256(AggregatorInterface(oracles[_tokenIn]).latestAnswer());
        uint256 tokenOutPrice = uint256(AggregatorInterface(oracles[_tokenOut]).latestAnswer());

        return (_amountOut * tokenOutPrice / tokenInPrice) * 100 / 99; // 1% fee burnt
    }

    function swapTokenFrom(address _tokenIn, address _tokenOut, uint256 _amountIn) external {
        uint256 amountOut = getAmountOut(_tokenIn, _tokenOut, _amountIn);

        TradingCompetitionERC20(_tokenIn).burn(msg.sender, _amountIn);
        TradingCompetitionERC20(_tokenOut).mint(msg.sender, amountOut);

        emit Swap(_tokenIn, _tokenOut, _amountIn, amountOut);
    }

    function swapTokenTo(address _tokenIn, address _tokenOut, uint256 _amountOut) external {
        uint256 amountIn = getAmountOut(_tokenIn, _tokenOut, _amountOut);

        TradingCompetitionERC20(_tokenIn).burn(msg.sender, amountIn);
        TradingCompetitionERC20(_tokenOut).mint(msg.sender, _amountOut);

        emit Swap(_tokenIn, _tokenOut, amountIn, _amountOut);
    }

    //

    function isMinter(address _user) external view returns(bool) {
        return _user == address(this) || _minters.contains(_user);
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
