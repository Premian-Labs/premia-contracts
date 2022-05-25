// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IOFTCore} from "./IOFTCore.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Interface of the OFT standard
 */
interface IOFT is IOFTCore, IERC20 {

}
