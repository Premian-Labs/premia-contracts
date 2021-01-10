// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PremiaErc20 is ERC20 {
    constructor() ERC20("Premia", "PREMIA") {
        _mint(msg.sender, 1e26); // 100m
    }
}