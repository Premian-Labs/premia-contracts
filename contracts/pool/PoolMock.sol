// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/contracts/introspection/ERC165Storage.sol';
import '@solidstate/contracts/contracts/token/ERC20/ERC20.sol';
import '@solidstate/contracts/contracts/token/ERC20/ERC20MetadataStorage.sol';

import './Pool.sol';

contract PoolMock is Pool {
  using ERC165Storage for ERC165Storage.Layout;

  constructor (
    address owner,
    address base,
    address underlying
  ) {
    OwnableStorage.layout().owner = owner;

    {
      PoolStorage.Layout storage l = PoolStorage.layout();
      l.pair = msg.sender;
      l.base = base;
      l.underlying = underlying;
    }

    {
      ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();

      string memory symbolUnderlying = ERC20(underlying).symbol();
      string memory symbolBase = ERC20(base).symbol();

      l.name = string(abi.encodePacked(
        'Median Liquidity: ',
        symbolUnderlying,
        '/',
        symbolBase
      ));

      l.symbol = string(abi.encodePacked(
        'MED-',
        symbolUnderlying,
        symbolBase
      ));

      l.decimals = 18;
    }

    {
      ERC165Storage.Layout storage l = ERC165Storage.layout();
      l.setSupportedInterface(type(IERC165).interfaceId, true);
      l.setSupportedInterface(type(IERC1155).interfaceId, true);
    }
  }

  function tokenIdFor (
    uint192 strikePrice,
    uint64 maturity
  ) external view returns (uint) {
    return _tokenIdFor(strikePrice, maturity);
  }
}
