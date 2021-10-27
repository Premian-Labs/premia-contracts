// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {PremiaMiningStorage} from "./PremiaMiningStorage.sol";

interface IPremiaMining {
    function addPremiaRewards(uint256 _amount) external;

    function premiaRewardsAvailable() external view returns (uint256);

    function getTotalAllocationPoints() external view returns (uint256);

    function getPoolInfo(address pool, bool isCallPool)
        external
        view
        returns (PremiaMiningStorage.PoolInfo memory);

    function getPremiaPerBlock() external view returns (uint256);

    function addPool(address _pool, uint256 _allocPoints) external;

    function setPoolAllocPoints(address _pool, uint256 _allocPoints) external;

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
