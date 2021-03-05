// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IPremiaUncutErc20 is IERC20 {
    function getTokenPrice(address _token) external view returns(uint256);
    function mint(address _account, uint256 _amount) external;
    function mintReward(address _account, address _token, uint256 _feePaid, uint8 _decimals) external;
}