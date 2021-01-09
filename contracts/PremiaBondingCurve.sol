// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

// This contract is forked from Hegic's LinearBondingCurve
contract PremiaBondingCurve {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public premiaPBS;
    IERC20 public premia;
    address payable public treasury;

    bool public isInitialized = false;

    uint256 internal immutable K;
    uint256 internal immutable START_PRICE;
    uint256 public soldAmount;

    event Bought(address indexed account, uint256 amount, uint256 ethAmount);
    event Sold(address indexed account, uint256 amount, uint256 ethAmount, uint256 comission);

    constructor(IERC20 _premia, address payable _treasury, uint256 _startPrice, uint256 _k) {
        premia = _premia;
        treasury = _treasury;
        START_PRICE = _startPrice;
        K = _k;
    }

    function buy(uint256 tokenAmount) external payable {
        require(isInitialized, "Not initialized");
        uint256 nextSold = soldAmount.add(tokenAmount);
        uint256 ethAmount = s(soldAmount, nextSold);
        soldAmount = nextSold;
        require(msg.value >= ethAmount, "Value is too small");
        premia.safeTransfer(msg.sender, tokenAmount);
        if (msg.value > ethAmount)
            msg.sender.transfer(msg.value.sub(ethAmount));
        emit Bought(msg.sender, tokenAmount, ethAmount);
    }

    function sell(uint256 tokenAmount) external {
        uint256 nextSold = soldAmount.sub(tokenAmount);
        uint256 ethAmount = s(nextSold, soldAmount);
        uint256 commission = ethAmount.div(10);
        uint256 refund = ethAmount.sub(commission);
        require(commission > 0);

        soldAmount = nextSold;
        premia.safeTransferFrom(msg.sender, address(this), tokenAmount);
        treasury.transfer(commission);
        msg.sender.transfer(refund);
        emit Sold(msg.sender, tokenAmount, refund, commission);
    }

    function s(uint256 x0, uint256 x1) public view returns (uint256) {
        require(x1 > x0);
        return x1.add(x0).mul(x1.sub(x0))
        .div(2).div(K)
        .add(START_PRICE.mul(x1.sub(x0)))
        .div(1e18);
    }
}
