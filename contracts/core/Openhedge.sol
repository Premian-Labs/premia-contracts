// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;
pragma abicoder v2;

import '@solidstate/contracts/contracts/access/OwnableStorage.sol';
import '@solidstate/contracts/contracts/architecture/diamond/DiamondBase.sol';

import './PairManagerStorage.sol';

/**
 * @title Openhedge core contract
 * @dev based on the EIP2535 Diamond standard
 */
contract Openhedge is DiamondBase {
  using DiamondBaseStorage for DiamondBaseStorage.Layout;

  /**
   * @notice deploy contract and connect given diamond facets
   * @param cuts diamond cuts to add at deployment
   * @param pairImplementation implementaion Pair contract
   */
  constructor (
    DiamondBaseStorage.FacetCut[] memory cuts,
    address pairImplementation
  ) {
    OwnableStorage.layout().owner = msg.sender;
    DiamondBaseStorage.layout().diamondCut(cuts);
    PairManagerStorage.layout().implementation = pairImplementation;
  }
}
