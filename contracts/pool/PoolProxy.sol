// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/introspection/ERC165Storage.sol';
import '@solidstate/contracts/proxy/managed/ManagedProxyOwnable.sol';
import '@solidstate/contracts/token/ERC20/ERC20.sol';
import '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';
import '@solidstate/contracts/token/ERC1155/IERC1155.sol';

import '../core/IProxyManager.sol';
import './PoolStorage.sol';

/**
 * @title Upgradeable proxy with centrally controlled Pool implementation
 */
contract PoolProxy is ManagedProxyOwnable {
  using ERC165Storage for ERC165Storage.Layout;

  constructor (
    address owner,
    address base,
    address underlying
  ) ManagedProxy(IProxyManager.getPoolImplementation.selector) {
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
}
