// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import {ERC20} from '@solidstate/contracts/token/ERC20/ERC20.sol';
import {ERC20Permit} from '@solidstate/contracts/token/ERC20/ERC20Permit.sol';
import {ERC20MetadataStorage} from '@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol';

// Only used for unit tests
contract TestErc20 is ERC20, ERC20Permit {
    using ERC20MetadataStorage for ERC20MetadataStorage.Layout;

    constructor(uint8 _decimals) {
        ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();

        l.setName("Test");
        l.setSymbol("TEST");
        l.setDecimals(_decimals);
    }

    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }
}
