// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import '@solidstate/contracts/contracts/access/OwnableStorage.sol';

import '../core/ProxyManager.sol';

/**
 * @title Upgradeable proxy with centrally controlled Pair implementation
 * @dev uses Ownable storage location
 */
contract PairProxy {
  constructor () {
    OwnableStorage.layout().owner = msg.sender;
  }

  fallback () virtual external payable {
    address implementation = ProxyManager(
      OwnableStorage.layout().owner
    ).getPairImplementation();

    assembly {
      calldatacopy(0, 0, calldatasize())
      let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())

      switch result
        case 0 { revert(0, returndatasize()) }
        default { return(0, returndatasize()) }
    }
  }
}
