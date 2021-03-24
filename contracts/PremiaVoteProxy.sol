// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interface/IPremiaFeeDiscount.sol";

contract PremiaVoteProxy {
    using SafeMath for uint256;

    IERC20 public premia;
    IERC20 public xPremia;
    IPremiaFeeDiscount public premiaFeeDiscount;

    constructor(ERC20 _premia, ERC20 _xPremia, IPremiaFeeDiscount _premiaFeeDiscount) {
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

        uint256 totalXPremia = xPremia.balanceOf(_voter).add(premiaFeeDiscount.userInfo(_voter).balance);
        uint256 premiaStaked = totalXPremia.mul(1e18).div(xPremia.totalSupply()).mul(premia.balanceOf(address(xPremia))).div(1e18);
        _votes = _votes.add(premiaStaked);

        return _votes;
    }
}