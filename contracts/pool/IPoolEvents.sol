// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPoolEvents {
    event Purchase(
        address indexed user,
        uint256 longTokenId,
        uint256 contractSize,
        uint256 baseCost,
        uint256 feeCost,
        int128 spot64x64
    );

    event Sell(
        address indexed user,
        uint256 longTokenId,
        uint256 contractSize,
        uint256 baseCost,
        uint256 feeCost,
        int128 spot64x64
    );

    event Exercise(
        address indexed user,
        uint256 longTokenId,
        uint256 contractSize,
        uint256 exerciseValue,
        uint256 fee
    );

    event Underwrite(
        address indexed underwriter,
        address indexed longReceiver,
        uint256 shortTokenId,
        uint256 intervalContractSize,
        uint256 intervalPremium,
        bool isManualUnderwrite
    );

    event AssignExercise(
        address indexed underwriter,
        uint256 shortTokenId,
        uint256 freedAmount,
        uint256 intervalContractSize,
        uint256 fee
    );

    event AssignSale(
        address indexed underwriter,
        uint256 shortTokenId,
        uint256 freedAmount,
        uint256 intervalContractSize
    );

    event Deposit(address indexed user, bool isCallPool, uint256 amount);

    event Withdrawal(
        address indexed user,
        bool isCallPool,
        uint256 depositedAt,
        uint256 amount
    );

    event FeeWithdrawal(bool indexed isCallPool, uint256 amount);

    event APYFeeReserved(
        address underwriter,
        uint256 shortTokenId,
        uint256 amount
    );

    event APYFeePaid(address underwriter, uint256 shortTokenId, uint256 amount);

    event Annihilate(uint256 shortTokenId, uint256 amount);

    event UpdateCLevel(
        bool indexed isCall,
        int128 cLevel64x64,
        int128 oldLiquidity64x64,
        int128 newLiquidity64x64
    );

    event UpdateSteepness(int128 steepness64x64, bool isCallPool);

    event UpdateSpotOffset(int128 spotOffset64x64);
}
