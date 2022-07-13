// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";

import {IPremiaStaking} from "./staking/IPremiaStaking.sol";

contract PremiaVoteProxy {
    address internal immutable VE_PREMIA;

    constructor(address vePremia) {
        VE_PREMIA = vePremia;
    }

    function decimals() external pure returns (uint8) {
        return uint8(18);
    }

    function name() external pure returns (string memory) {
        return "PREMIAVOTE";
    }

    function symbol() external pure returns (string memory) {
        return "PREMIAVOTE";
    }

    function totalSupply() external view returns (uint256) {
        return IPremiaStaking(VE_PREMIA).getTotalPower();
    }

    function balanceOf(address voter) external view returns (uint256) {
        return IPremiaStaking(VE_PREMIA).getUserPower(voter);
    }
}
