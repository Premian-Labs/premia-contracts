// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";

import {IFeeDiscount} from "./staking/IFeeDiscount.sol";

contract PremiaVoteProxy {
    IERC20 public premia;
    IERC20 public xPremia;
    IFeeDiscount public premiaFeeDiscount;

    constructor(
        IERC20 _premia,
        IERC20 _xPremia,
        IFeeDiscount _premiaFeeDiscount
    ) {
        premia = _premia;
        xPremia = _xPremia;
        premiaFeeDiscount = _premiaFeeDiscount;
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
        return premia.totalSupply();
    }

    function balanceOf(address _voter) external view returns (uint256) {
        uint256 _votes = premia.balanceOf(_voter);

        uint256 totalXPremia = xPremia.balanceOf(_voter) +
            premiaFeeDiscount.userInfo(_voter).balance;
        uint256 premiaStaked = (((totalXPremia * 1e18) /
            xPremia.totalSupply()) * premia.balanceOf(address(xPremia))) / 1e18;
        _votes += premiaStaked;

        return _votes;
    }
}
