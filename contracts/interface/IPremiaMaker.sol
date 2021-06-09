// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IUniswapV2Router02} from '../uniswapV2/interfaces/IUniswapV2Router02.sol';

interface IPremiaMaker {
    function premia() external view returns(address);
    function premiaStaking() external view returns(address);
    function treasury() external view returns(address);
    function treasuryFee() external view returns(uint256);
    function customPath(address _token) external view returns(address[] memory);

    function setCustomPath(address _token, address[] memory _path) external;
    function setTreasuryFee(uint256 _fee) external;
    function addWhitelistedRouter(address[] memory _addr) external;
    function removeWhitelistedRouter(address[] memory _addr) external;

    function getWhitelistedRouters() external view returns(address[] memory);
    function convert(IUniswapV2Router02 _router, address _token) external;
}
