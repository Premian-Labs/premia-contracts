// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract PremiaBondingCurve {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public premiaPBS;
    IERC20 public premia;


    uint256 public startPrice;
    bool public isInitialized = false;

    constructor(IERC20 _premia, address _premiaPBS) {
        premia = _premia;
        premiaPBS = _premiaPBS;
    }

    function initialize(uint256 _startPrice) external {
        require(isInitialized == false, "Already initialized");
        require(msg.sender == premiaPBS, "Not allowed");
        startPrice = _startPrice;
        isInitialized = true;
    }
}
