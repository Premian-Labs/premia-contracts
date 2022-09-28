// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IFeeCollector} from "./interfaces/IFeeCollector.sol";
import {IPoolIO} from "./pool/IPoolIO.sol";

// Contract used to facilitate withdrawal of fees to multisig on L2, in order to bridge to L1
contract FeeCollector is IFeeCollector {
    using SafeERC20 for IERC20;

    // The treasury address which will receive a portion of the protocol fees
    address public immutable RECEIVER;

    constructor(address _receiver) {
        RECEIVER = _receiver;
    }

    function withdraw(address[] memory pools, address[] memory tokens)
        external
    {
        for (uint256 i = 0; i < pools.length; i++) {
            IPoolIO(pools[i]).withdrawFees();
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amount = IERC20(tokens[i]).balanceOf(address(this));

            if (amount > 0) {
                IERC20(tokens[i]).safeTransfer(RECEIVER, amount);
            }
        }
    }
}
