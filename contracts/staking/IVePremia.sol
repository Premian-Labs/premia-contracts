// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {VePremiaStorage} from "./VePremiaStorage.sol";

interface IVePremia {
    /**
     * @notice get total voting power across all users
     * @return total voting power across all users
     */
    function getTotalVotingPower() external view returns (uint256);

    /**
     * @notice get total votes for specific pools
     * @param pools addresses of the pools
     * @return total votes for specific pools
     */
    function getPoolVotes(address[] memory pools)
        external
        view
        returns (uint256[2][] memory);

    /**
     * @notice get voting power of a user
     * @param user user for which to get voting power
     * @return voting power of the user
     */
    function getUserVotingPower(address user) external view returns (uint256);

    /**
     * @notice get votes of user
     * @param user user from which to get votes
     * @return votes of user
     */
    function getUserVotes(address user)
        external
        view
        returns (VePremiaStorage.Vote[] memory);

    /**
     * @notice add or remove votes, in the limit of the user voting power
     * @param votes votes to cast
     */
    function castVotes(VePremiaStorage.Vote[] memory votes) external;
}
