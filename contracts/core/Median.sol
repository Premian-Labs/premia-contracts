// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/proxy/diamond/DiamondBase.sol';

import './ProxyManagerStorage.sol';

/**
 * @title Median core contract
 * @dev based on the EIP2535 Diamond standard
 */
contract Median is DiamondBase {
  using DiamondBaseStorage for DiamondBaseStorage.Layout;

  /**
   * @notice deploy contract and connect given diamond facets
   * @param cuts diamond cuts to add at deployment
   * @param pairImplementation implementaion Pair contract
   * @param poolImplementation implementaion Pool contract
   */
  constructor (
    DiamondBaseStorage.FacetCut[] memory cuts,
    address pairImplementation,
    address poolImplementation
  ) {
    OwnableStorage.layout().owner = msg.sender;
    DiamondBaseStorage.layout().diamondCut(cuts);

    {
      ProxyManagerStorage.Layout storage l = ProxyManagerStorage.layout();
      l.pairImplementation = pairImplementation;
      l.poolImplementation = poolImplementation;
    }
  }
}
