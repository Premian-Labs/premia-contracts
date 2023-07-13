// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20Base, ERC20BaseStorage} from "@solidstate/contracts/token/ERC20/base/ERC20Base.sol";
import {SolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";

import {OFTCore} from "./OFTCore.sol";
import {IOFT} from "./IOFT.sol";

// override decimal() function is needed
contract OFT is OFTCore, SolidStateERC20, IOFT {
    constructor(address lzEndpoint) OFTCore(lzEndpoint) {}

    function circulatingSupply()
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _totalSupply();
    }

    function _debitFrom(
        address from,
        uint16,
        bytes memory,
        uint256 amount
    ) internal virtual override {
        address spender = msg.sender;

        if (from != spender) {
            unchecked {
                mapping(address => uint256)
                    storage allowances = ERC20BaseStorage.layout().allowances[
                        from
                    ];

                uint256 allowance = allowances[spender];
                if (amount > allowance) revert OFT_InsufficientAllowance();

                _approve(
                    from,
                    spender,
                    allowances[spender] = allowance - amount
                );
            }
        }

        _burn(from, amount);
    }

    function _creditTo(
        uint16,
        address toAddress,
        uint256 amount
    ) internal virtual override {
        _mint(toAddress, amount);
    }
}
