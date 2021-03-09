// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKeep3rV1Helper {
    function getQuoteLimit(uint gasUsed) external view returns (uint);
}

interface IKeep3rV1 {
    function isMinKeeper(address keeper, uint minBond, uint earned, uint age) external returns (bool);
    function receipt(address credit, address keeper, uint amount) external;
    function unbond(address bonding, uint amount) external;
    function withdraw(address bonding) external;
    function bonds(address keeper, address credit) external view returns (uint);
    function unbondings(address keeper, address credit) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function jobs(address job) external view returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function worked(address keeper) external;
    function KPRH() external view returns (IKeep3rV1Helper);
}