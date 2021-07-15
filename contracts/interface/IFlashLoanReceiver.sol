// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFlashLoanReceiver {
    function execute(
        address _tokenAddress,
        uint256 _amount,
        uint256 _amountWithFee
    ) external;
}
