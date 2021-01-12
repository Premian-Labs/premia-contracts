// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import "../ERC20Permit.sol";

// Only used for unit tests
contract TestErc20 is ERC20Permit {
    constructor() ERC20("Test", "TEST") {
    }

    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }
}