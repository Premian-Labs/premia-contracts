// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from '@solidstate/contracts/access/OwnableStorage.sol';
import {ERC165Storage} from '@solidstate/contracts/introspection/ERC165Storage.sol';
import {ERC20} from '@solidstate/contracts/token/ERC20/ERC20.sol';
import {ERC20MetadataStorage} from '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';

import {Pool} from '../pool/Pool.sol';

contract PoolMock is Pool {
  using ERC165Storage for ERC165Storage.Layout;

  constructor () Pool(address(0), address(1)) {}

  function tokenIdFor (
    TokenType tokenType,
    uint64 maturity,
    int128 strikePrice
  ) external pure returns (uint) {
    return _tokenIdFor(tokenType, maturity, strikePrice);
  }

  function parametersFor (
    uint256 tokenId
  ) external pure returns (TokenType, uint64, int128) {
    return _parametersFor(tokenId);
  }

  function mint (
    address account,
    uint amount
  ) external {
    _mint(account, amount);
  }

  function burn (
    address account,
    uint amount
  ) external {
    _burn(account, amount);
  }

  function mint (
    address account,
    uint id,
    uint amount
  ) external {
    _mint(account, id, amount, '');
  }

  function burn (
    address account,
    uint id,
    uint amount
  ) external {
    _burn(account, id, amount);
  }
}
