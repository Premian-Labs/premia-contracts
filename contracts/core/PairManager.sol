// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableInternal.sol';

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
   * TODO: assets
   * @return deployment address
   */
  function deployPair (
    address,
    address
  ) external onlyOwner returns (address) {
    PairProxy pair = new PairProxy();
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
