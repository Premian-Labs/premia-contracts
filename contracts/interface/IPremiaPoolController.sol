// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./IPoolControllerChild.sol";
import "./IPremiaMiningV2.sol";
import "../amm/PremiaLiquidityPool.sol";
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
    }

    function upgradeController(IPoolControllerChild[] memory _children, address _newController) external;
    function setPermissions(address[] memory _addr, Permissions[] memory _permissions) external;
    function setCustomSwapPath(address _collateralToken, address _token, address[] memory _path) external;
    function setDesignatedSwapRouter(address _tokenA, address _tokenB, IUniswapV2Router02 _router) external;
    function setLoanToValueRatio(address _collateralToken, uint256 _loanToValueRatio) external;
    function setPremiaMining(IPremiaMiningV2 _premiaMining) external;

    function getPermissions(address _user) external view returns (Permissions memory);
    function getCustomSwapPath(address _fromToken, address _toToken) external view returns (address[] memory);
    function getDesignedSwapRouter(address _fromToken, address _toToken) external view returns (IUniswapV2Router02);
    function getLoanToValueRatio(address _token) external view returns (uint256);
    function getCallPools() external view returns (PremiaLiquidityPool[] memory);
    function getPutPools() external view returns (PremiaLiquidityPool[] memory);

    function deposit(DepositArgs[] memory _deposits) external;
    function withdrawExpired(WithdrawExpiredArgs[] memory _withdrawals) external;
}