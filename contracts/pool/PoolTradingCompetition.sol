// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./Pool.sol";

contract PoolTradingCompetition is Pool {
    constructor (address weth, address feeReceiver, int128 fee64x64) Pool(weth, feeReceiver, fee64x64) { }

    function _beforeTokenTransfer (
        address operator,
        address from,
        address to,
        uint[] memory ids,
        uint[] memory amounts,
        bytes memory data
    ) override internal {
        require(from == address(0) || to == address(0), 'Transfer not allowed');
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
