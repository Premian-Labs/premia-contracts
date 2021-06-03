// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from '@solidstate/contracts/access/OwnableStorage.sol';
import {ERC165Storage} from '@solidstate/contracts/introspection/ERC165Storage.sol';
import {ManagedProxyOwnable, ManagedProxy} from '@solidstate/contracts/proxy/managed/ManagedProxyOwnable.sol';
import {ERC20MetadataStorage} from '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';
import {IERC20Metadata} from '@solidstate/contracts/token/ERC20/IERC20Metadata.sol';
import {IERC1155} from '@solidstate/contracts/token/ERC1155/IERC1155.sol';
import {IERC165} from '@solidstate/contracts/introspection/IERC165.sol';

import {IProxyManager} from '../core/IProxyManager.sol';
import {PoolStorage} from './PoolStorage.sol';

import { OptionMath } from '../libraries/OptionMath.sol';

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
      l.treasury = owner;
      l.pair = msg.sender;
      l.underlying = underlying;
      l.underlyingDecimals = IERC20Metadata(underlying).decimals();
      l.cLevel64x64 = OptionMath.INITIAL_C_LEVEL_64x64;
    }

    {
      ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();

      string memory symbolBase = IERC20Metadata(base).symbol();
      string memory symbolUnderlying = IERC20Metadata(underlying).symbol();

      l.name = string(abi.encodePacked(
        'Premia Liquidity: ',
        symbolUnderlying,
        '/',
        symbolBase
      ));

      l.symbol = string(abi.encodePacked(
        'PREMIA-',
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
