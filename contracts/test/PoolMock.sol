// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from '@solidstate/contracts/access/OwnableStorage.sol';
import {ERC165Storage} from '@solidstate/contracts/introspection/ERC165Storage.sol';
import {ERC20} from '@solidstate/contracts/token/ERC20/ERC20.sol';
import {ERC20MetadataStorage} from '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';

import {Pool} from '../pool/Pool.sol';
import {PoolStorage} from '../pool/PoolStorage.sol';

contract PoolMock is Pool {
  using ERC165Storage for ERC165Storage.Layout;

  // TODO: pass non-zero fee
  // TODO: confirm batching period
  constructor (address weth) Pool(address(weth), address(1), 0, 260) {}

  function tokenIdFor (
    PoolStorage.TokenType tokenType,
    uint64 maturity,
    int128 strikePrice
  ) external pure returns (uint) {
    // TODO: move to dedicated test contract
    return PoolStorage.formatTokenId(tokenType, maturity, strikePrice);
  }

  function parametersFor (
    uint256 tokenId
  ) external pure returns (PoolStorage.TokenType, uint64, int128) {
    // TODO: move to dedicated test contract
    return PoolStorage.parseTokenId(tokenId);
  }

  function mint (
    address account,
    uint256 tokenId,
    uint256 amount
  ) external {
    _mint(account, tokenId, amount, '');
  }

  function burn (
    address account,
    uint256 tokenId,
    uint256 amount
  ) external {
    _burn(account, tokenId, amount);
  }

  function addUnderwriter (
    address account,
    bool isCallPool
  ) external {
    PoolStorage.addUnderwriter(PoolStorage.layout(), account, isCallPool);
  }

  function removeUnderwriter (
    address account,
    bool isCallPool
  ) external {
    PoolStorage.removeUnderwriter(PoolStorage.layout(), account, isCallPool);
  }

  function getUnderwriter () external view returns(address) {
    return PoolStorage.layout().liquidityQueueAscending[true][address(0)];
  }
}
