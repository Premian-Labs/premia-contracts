// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableInternal.sol';

import '../pair/Pair.sol';
import '../pair/PairProxy.sol';
import './PairManagerStorage.sol';

/**
 * @title Options pair management contract
 * @dev deployed standalone and connected to Openhedge as diamond facet
 */
contract PairManager is OwnableInternal {
  event PairDeployment (address pair);

  /**
   * @notice deploy PairProxy contract
   * @param asset0 asset in pair
   * @param asset1 asset in pair
   * TODO: unrestrict
   * @return deployment address
   */
  function deployPair (
    address asset0,
    address asset1
  ) external onlyOwner returns (address) {
    PairProxy pair = new PairProxy();
    Pair(address(pair)).initialize(asset0, asset1);
    emit PairDeployment(address(pair));
    return address(pair);
  }

  /**
   * @notice get address of Pair implementation contract
   * @dev TODO: override from interface
   * @return implementation address
   */
  function getPairImplementation () external view returns (address) {
    return PairManagerStorage.layout().implementation;
  }
}
