// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/proxy/diamond/Diamond.sol';

import './ProxyManagerStorage.sol';

/**
 * @title Median core contract
 * @dev based on the EIP2535 Diamond standard
 */
contract Median is Diamond {

  /**
   * @notice deploy contract and connect given diamond facets
   * @param pairImplementation implementaion Pair contract
   * @param poolImplementation implementaion Pool contract
   */
  constructor (
    address pairImplementation,
    address poolImplementation
  ) {
    OwnableStorage.layout().owner = msg.sender;

    {
      ProxyManagerStorage.Layout storage l = ProxyManagerStorage.layout();
      l.pairImplementation = pairImplementation;
      l.poolImplementation = poolImplementation;
    }
  }
}
