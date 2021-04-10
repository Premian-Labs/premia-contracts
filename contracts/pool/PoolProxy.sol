// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/introspection/ERC165Storage.sol';
import '@solidstate/contracts/proxy/managed/ManagedProxyOwnable.sol';
import '@solidstate/contracts/token/ERC20/IERC20Metadata.sol';
import '@solidstate/contracts/token/ERC1155/IERC1155.sol';

import '../core/IProxyManager.sol';
import './PoolStorage.sol';

/**
 * @title Upgradeable proxy with centrally controlled Pool implementation
 */
contract PoolProxy is ManagedProxyOwnable {
  using ERC165Storage for ERC165Storage.Layout;

  // 64x64 fixed point representeation of 2e
  int128 private constant INITIAL_C_LEVEL_64x64 = 0x56fc2a2c515da32ea;

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
      l.baseDecimals = IERC20Metadata(base).decimals();
      l.underlyingDecimals = IERC20Metadata(underlying).decimals();
      l.cLevel64x64 = INITIAL_C_LEVEL_64x64;
    }

    {
      ERC165Storage.Layout storage l = ERC165Storage.layout();
      l.setSupportedInterface(type(IERC165).interfaceId, true);
      l.setSupportedInterface(type(IERC1155).interfaceId, true);
    }
  }
}
