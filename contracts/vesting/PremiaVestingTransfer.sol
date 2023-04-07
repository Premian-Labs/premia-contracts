// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

interface IOldContract {
    function withdraw() external;
}

contract PremiaVestingTransfer {
    using SafeERC20 for IERC20;

    address public constant PREMIA = 0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70;
    address public immutable OLD_CONTRACT;
    address public immutable NEW_CONTRACT;

    constructor(address oldContract, address newContract) {
        OLD_CONTRACT = oldContract;
        NEW_CONTRACT = newContract;
    }

    function transfer() public {
        IOldContract(OLD_CONTRACT).withdraw();
        IERC20(PREMIA).safeTransfer(
            NEW_CONTRACT,
            IERC20(PREMIA).balanceOf(address(this))
        );
    }
}
