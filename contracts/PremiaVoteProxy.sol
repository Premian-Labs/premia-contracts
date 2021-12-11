// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";

import {IFeeDiscount} from "./staking/IFeeDiscount.sol";
import {IPremiaStaking} from "./staking/IPremiaStaking.sol";

contract PremiaVoteProxy {
    address internal immutable PREMIA;
    address internal immutable xPREMIA;
    address internal immutable FEE_DISCOUNT;

    constructor(
        address _premia,
        address _xPremia,
        address _feeDiscount
    ) {
        PREMIA = _premia;
        xPREMIA = _xPremia;
        FEE_DISCOUNT = _feeDiscount;
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
        return IERC20(PREMIA).totalSupply();
    }

    function balanceOf(address _voter) external view returns (uint256) {
        uint256 _votes = IERC20(PREMIA).balanceOf(_voter);

        uint256 totalXPremia = IERC20(xPREMIA).balanceOf(_voter) +
            IFeeDiscount(FEE_DISCOUNT).getUserInfo(_voter).balance;

        uint256 xPremiaToPremiaRatio = IPremiaStaking(xPREMIA)
            .getXPremiaToPremiaRatio();

        _votes += (totalXPremia * xPremiaToPremiaRatio) / 1e18;

        return _votes;
    }
}
