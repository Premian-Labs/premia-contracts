// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';

interface IPremiaAMM {
    struct DepositArgs {
        address pool;
        IPremiaLiquidityPool.TokenPair[] pairs;
        uint256[] amounts;
        uint256 lockExpiration;
    }

    struct WithdrawExpiredArgs {
        address pool;
        IPremiaLiquidityPool.TokenPair[] pairs;
    }

    enum SaleSide {Buy, Sell}

    ////////////
    // Events //
    ////////////

    event Bought(address indexed user, address indexed optionContract, uint256 indexed optionId, uint256 amount, uint256 optionPrice);
    event Sold(address indexed user, address indexed optionContract, uint256 indexed optionId, uint256 amount, uint256 optionPrice);

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

    function customSwapPaths(address _collateral, address _token) external view returns(address[] memory);
    function defaultSwapRouter() external view returns(IUniswapV2Router02);
    function loanToValueRatios(address _token) external view returns(uint256);

    function getDesignatedSwapRouter(address _tokenA, address _tokenB) external view returns(IUniswapV2Router02);
    function getCallPools() external view returns(IPremiaLiquidityPool[] memory);
    function getPutPools() external view returns(IPremiaLiquidityPool[] memory);
    function getCallReserves(address _optionContract, uint256 _optionId) external view returns (uint256);
    function getPutReserves(address _optionContract, uint256 _optionId) external view returns (uint256 reserveAmount);
    function getCallMaxBuy(address _optionContract, uint256 _optionId) external view returns (uint256);
    function getCallMaxSell(address _optionContract, uint256 _optionId) external view returns (uint256);
    function getPutMaxBuy(address _optionContract, uint256 _optionId) external view returns (uint256);

    function getPutMaxSell(address _optionContract, uint256 _optionId) external view returns (uint256);
    function priceOption(IPremiaOption _optionContract, uint256 _optionId, SaleSide _side, uint256 _amount) external view returns (uint256 optionPrice);

    //////////////////////////////////////////////////

    function buy(address _optionContract, IPremiaOption.OptionWriteArgs memory _option, uint256 _maxPremiumAmount, address _referrer) external returns(uint256);
    function sell(address _optionContract, uint256 _optionId, uint256 _amount, uint256 _minPremiumAmount) external;
    function depositLiquidity(DepositArgs[] memory _deposits) external;
    function withdrawExpiredLiquidity(WithdrawExpiredArgs[] memory _withdrawals) external;
}