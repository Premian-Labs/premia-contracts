// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

/**
 * @title Upgradeable proxy with centrally controlled implementation
 */
abstract contract ManagedProxy {
  fallback () external payable {
    address implementation = _implementation();

    assembly {
      calldatacopy(0, 0, calldatasize())
      let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())

      switch result
        case 0 { revert(0, returndatasize()) }
        default { return(0, returndatasize()) }
    }
  }

  function _implementation () virtual internal returns (address);
}
