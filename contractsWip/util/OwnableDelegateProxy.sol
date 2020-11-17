pragma solidity >=0.6.0;

import './OwnedUpgradeabilityProxy.sol';

contract OwnableDelegateProxy is OwnedUpgradeabilityProxy {
  constructor(
    address owner,
    address initialImplementation,
    bytes calldata _calldata
  ) public {
    setUpgradeabilityOwner(owner);
    _upgradeTo(initialImplementation);
    require(initialImplementation.delegatecall(_calldata));
  }
}
