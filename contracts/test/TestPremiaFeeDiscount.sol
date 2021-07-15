// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// Used to mock PremiaStaking contract
contract TestPremiaFeeDiscount {
    uint256 public discount;

    function setDiscount(uint256 _value) external {
        discount = _value;
    }

    function getDiscount(address) external view returns (uint256) {
        return discount;
    }
}
