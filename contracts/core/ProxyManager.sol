// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableInternal} from '@solidstate/contracts/access/OwnableInternal.sol';

import {IProxyManager} from './IProxyManager.sol';
import {ProxyManagerStorage} from './ProxyManagerStorage.sol';
import {PoolProxy} from '../pool/PoolProxy.sol';
import {OptionMath} from '../libraries/OptionMath.sol';

/**
 * @title Options pair management contract
 * @dev deployed standalone and connected to Premia as diamond facet
 */
contract ProxyManager is IProxyManager, OwnableInternal {
  using ProxyManagerStorage for ProxyManagerStorage.Layout;

  event DeployPool (
    address indexed base,
    address indexed underlying,
    int128 indexed initialCLevel64x64,
    address baseOracle,
    address underlyingOracle,
    address pool
  );

  /**
   * @notice get address of Pool implementation contract for forwarding via PoolProxy
   * @return implementation address
   */
  function getPoolImplementation () override external view returns (address) {
    return ProxyManagerStorage.layout().poolImplementation;
  }

  /**
   * @notice get address of Pool contract for given assets
   * @param base base token
   * @param underlying underlying token
   * @return pool address (zero address if pool does not exist)
   */
  function getPool (
    address base,
    address underlying
  ) external view returns (address) {
    return ProxyManagerStorage.layout().getPool(base, underlying);
  }

  /**
   * @notice deploy PoolProxy contracts for the pair
   * @param base base token
   * @param underlying underlying token
   * @param baseOracle Chainlink price aggregator for base
   * @param underlyingOracle Chainlink price aggregator for underlying
   * TODO: unrestrict
   * @return deployment address
   */
  function deployPool (
    address base,
    address underlying,
    address baseOracle,
    address underlyingOracle,
    int128 price64x64,
    int128 emaLogReturns64x64
  ) external onlyOwner returns (address) {
    require(ProxyManagerStorage.layout().getPool(base, underlying) == address(0), "ProxyManager: Pool already exists");

    address pool = address(new PoolProxy(base, underlying, baseOracle, underlyingOracle, price64x64, emaLogReturns64x64));
    ProxyManagerStorage.layout().setPool(base, underlying, underlyingOracle);

    emit DeployPool(base, underlying, OptionMath.INITIAL_C_LEVEL_64x64, baseOracle, underlyingOracle, pool);

    return pool;
  }
}
