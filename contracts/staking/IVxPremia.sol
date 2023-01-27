// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {VxPremiaStorage} from "./VxPremiaStorage.sol";
import {IPremiaStaking} from "./IPremiaStaking.sol";

interface IVxPremia is IPremiaStaking {
    error VxPremia__InvalidPoolAddress();
    error VxPremia__InvalidVoteTarget();
    error VxPremia__NotEnoughVotingPower();

    event AddVote(
        address indexed voter,
        VxPremiaStorage.VoteVersion indexed version,
        bytes target,
        uint256 amount
    );
    event RemoveVote(
        address indexed voter,
        VxPremiaStorage.VoteVersion indexed version,
        bytes target,
        uint256 amount
    );

    /**
     * @notice get total votes for specific pools
     * @param version version of target (used to know how to decode data)
     * @param target ABI encoded target of the votes
     * @return total votes for specific pool
     */
    function getPoolVotes(
        VxPremiaStorage.VoteVersion version,
        bytes memory target
    ) external view returns (uint256);

    /**
     * @notice get votes of user
     * @param user user from which to get votes
     * @return votes of user
     */
    function getUserVotes(
        address user
    ) external view returns (VxPremiaStorage.Vote[] memory);

    /**
     * @notice add or remove votes, in the limit of the user voting power
     * @param votes votes to cast
     */
    function castVotes(VxPremiaStorage.Vote[] memory votes) external;
}
