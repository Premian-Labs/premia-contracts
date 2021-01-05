
// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

// Used to mock PremiaStaking contract
contract TestPremiaFeeDiscount {
    uint256 public discount;

    function setDiscount(uint256 _value) external {
        discount = _value;
    }

    function getDiscount(address _user) external returns(uint256) {
        return discount;
    }
}