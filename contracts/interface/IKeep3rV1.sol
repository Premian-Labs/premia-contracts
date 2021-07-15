// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKeep3rV1Helper {
    function getQuoteLimit(uint256 gasUsed) external view returns (uint256);
}

interface IKeep3rV1 {
    function isMinKeeper(
        address keeper,
        uint256 minBond,
        uint256 earned,
        uint256 age
    ) external returns (bool);

    function receipt(
        address credit,
        address keeper,
        uint256 amount
    ) external;

    function unbond(address bonding, uint256 amount) external;

    function withdraw(address bonding) external;

    function bonds(address keeper, address credit)
        external
        view
        returns (uint256);

    function unbondings(address keeper, address credit)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function jobs(address job) external view returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function worked(address keeper) external;

    function KPRH() external view returns (IKeep3rV1Helper);
}
