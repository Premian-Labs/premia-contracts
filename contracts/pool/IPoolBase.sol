// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";

interface IPoolBase is IMulticall {
    function FEE_RECEIVER_ADDRESS() external view returns (address);
}
