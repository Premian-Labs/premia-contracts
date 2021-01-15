// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IPremiaUncutErc20 is IERC20 {
    function mintReward(address _account, address _token, uint256 _feePaid) external;
}