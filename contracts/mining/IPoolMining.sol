// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolMining {
    function addPremiaRewards(uint256 _amount) external;

    function add(address _pool, uint256 _allocPoint) external;

    function set(address _pool, uint256 _allocPoint) external;

    function pendingPremia(
        address _pool,
        bool _isCallPool,
        address _user
    ) external view returns (uint256);

    function updatePool(
        address _pool,
        bool _isCallPool,
        uint256 _totalTVL
    ) external;

    function allocatePending(
        address _user,
        address _pool,
        bool _isCallPool,
        uint256 _userTVLOld,
        uint256 _userTVLNew,
        uint256 _totalTVL
    ) external;

    function claim(
        address _user,
        address _pool,
        bool _isCallPool,
        uint256 _userTVLOld,
        uint256 _userTVLNew,
        uint256 _totalTVL
    ) external;
}
