// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

contract PremiaBondingCurve {
    address public premiaInitialBootstrapContribution;

    uint256 public startPrice;
    bool public isInitialized = false;

    constructor(address _premiaInitialBootstrapContribution) public {
        premiaInitialBootstrapContribution = _premiaInitialBootstrapContribution;
    }

    function initialize(uint256 _startPrice) external {
        require(msg.sender == premiaInitialBootstrapContribution);
        startPrice = _startPrice;
        isInitialized = true;
    }
}
