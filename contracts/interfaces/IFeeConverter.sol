// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IFeeConverter {
    event Converted(
        address indexed account,
        address indexed token,
        uint256 inAmount,
        uint256 outAmount,
        uint256 treasuryAmount
    );

    event SetAuthorized(address indexed account, bool isAuthorized);

    function convert(
        address sourceToken,
        address callee,
        address allowanceTarget,
        bytes calldata data
    ) external;
}
