// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import "../ERC20Permit.sol";

// Only used for unit tests
contract TestErc20 is ERC20Permit {
    constructor(uint8 _decimals) ERC20("Test", "TEST") {
        _setupDecimals(_decimals);
    }

    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }
}