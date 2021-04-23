// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/introspection/ERC165Storage.sol';
import '@solidstate/contracts/token/ERC20/ERC20.sol';
import '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';

import '../pool/Pool.sol';

contract PoolMock is Pool {
  using ERC165Storage for ERC165Storage.Layout;

  constructor () Pool(address(0)) {}

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
