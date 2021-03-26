// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IPoolControllerChild.sol";
import "./IPremiaMiningV2.sol";
import "./IPremiaLiquidityPool.sol";
import "../uniswapV2/interfaces/IUniswapV2Router02.sol";

interface IPremiaPoolController {
    struct DepositArgs {
        address pool;
        address[] tokens;
        uint256[] amounts;
        uint256 lockExpiration;
    }

    struct WithdrawExpiredArgs {
        address pool;
        address[] tokens;
    }

    struct Permissions {
        bool canBorrow;
        bool canWrite;
        bool isWhitelistedToken;
        bool isWhitelistedPool;
        bool isWhitelistedOptionContract;
    }

    ///////////
    // Event //
    ///////////

    event DefaultSwapRouterUpdated(IUniswapV2Router02 indexed router);
    event PairSwapRouterUpdated(address indexed tokenA, address indexed tokenB, IUniswapV2Router02 indexed router);
    event CustomSwapPathUpdated(address indexed collateralToken, address indexed token, address[] path);
    event LoanToValueRatioUpdated(address indexed collateralToken, uint256 loanToValueRatio);
    event PremiaMiningUpdated(address indexed addr);

    event CallPoolAdded(address indexed addr);
    event CallPoolRemoved(address indexed addr);
    event PutPoolAdded(address indexed addr);
    event PutPoolRemoved(address indexed addr);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    function loanToValueRatios(address _token) external view returns (uint256);
    function customSwapPaths(address _fromToken, address _toToken) external view returns (address[] memory);

    function upgradeController(IPoolControllerChild[] memory _children, address _newController) external;
    function setPermissions(address[] memory _addr, Permissions[] memory _permissions) external;
    function setCustomSwapPath(address _collateralToken, address _token, address[] memory _path) external;
    function setDesignatedSwapRouter(address _tokenA, address _tokenB, IUniswapV2Router02 _router) external;
    function setLoanToValueRatio(address _collateralToken, uint256 _loanToValueRatio) external;
    function setPremiaMining(IPremiaMiningV2 _premiaMining) external;
    function getDesignatedSwapRouter(address _tokenA, address _tokenB) external returns(IUniswapV2Router02);

    function getCallPools() external view returns (IPremiaLiquidityPool[] memory);
    function getPutPools() external view returns (IPremiaLiquidityPool[] memory);

    function deposit(DepositArgs[] memory _deposits) external;
    function withdrawExpired(WithdrawExpiredArgs[] memory _withdrawals) external;
}