// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Only used for unit tests
contract TestErc20 is ERC20 {
    constructor() public ERC20("Test", "TEST") {
    }

    function mint(uint256 _amount) public {
        _mint(msg.sender, _amount);
    }
}