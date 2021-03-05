// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import "../ERC20Permit.sol";

// Only used for unit tests
contract TestErc20 is ERC20Permit {
    uint8 _tokenDecimals;

    constructor(uint8 _decimals) ERC20("Test", "TEST") {
        _tokenDecimals = _decimals;
    }

    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }
}