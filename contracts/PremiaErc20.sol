// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "./ERC20Permit.sol";

contract PremiaErc20 is ERC20Permit {
    constructor() ERC20("Premia", "PREMIA") {
        _mint(msg.sender, 1e26); // 100m
    }
}