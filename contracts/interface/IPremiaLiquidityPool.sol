// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';

import '../interface/IPriceOracleGetter.sol';
import "../uniswapV2/interfaces/IUniswapV2Router02.sol";

interface IPremiaLiquidityPool {
  struct UserDeposit {
    address user;
    address token;
    address denominator;
    uint256 amountToken;
    uint256 amountDenominator;
    uint256 lockExpiration;
  }

  struct Loan {
    address borrower;
    address token;
    uint256 amountOutstanding;
    address collateralToken;
    uint256 collateralHeld;
    uint256 tokenPrice;
    uint256 lockExpiration;
  }

  event Deposit(address indexed user, address indexed token, address indexed denominator, uint256 lockExpiration, uint256 amountToken, uint256 amountDenominator);
  event Withdraw(address indexed user, address indexed token, address indexed denominator, uint256 amountToken, uint256 amountDenominator);
  event Borrow(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed lockExpiration, uint256 amount);
  event RepayLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount);
  event LiquidateLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount, uint256 rewardFee);
  event WriteOption(address indexed writer, address indexed optionContract, uint256 indexed optionId, uint256 amount, address premiumToken, uint256 amountPremium);
  event UnwindOption(address indexed writer, address indexed optionContract, uint256 indexed optionId, uint256 amount);
  event UnlockCollateral(address indexed unlocker, address indexed optionContract, uint256 indexed optionId, uint256 amount);

  function addWhitelistedBorrowContracts(address[] memory _addr) external;
  function removeWhitelistedBorrowContracts(address[] memory _addr) external;
  function getWhitelistedBorrowContracts() external view returns(address[] memory);
  function addWhitelistedWriterContracts(address[] memory _addr) external;
  function removeWhitelistedWriterContracts(address[] memory _addr) external;
  function getWhitelistedWriterContracts() external view returns(address[] memory);
  function addWhitelistedRouterContracts(address[] memory _addr) external;
  function removeWhitelistedRouterContracts(address[] memory _addr) external;
  function getWhitelistedRouterContracts() external view returns(address[] memory);
  
  function setMaxExpiration(uint256 _max) external;
  function setLiquidatorReward(uint256 _reward) external;
  function setMaxPercentLiquidated(uint256 _maxPercent) external;
  function setCustomSwapPath(address collateralToken, address token, address[] memory path) external;
  function setPriceOracle(address priceOracleAddress) external;
  
  function getLoanHash(Loan memory loan) external pure returns(bytes32);
  function getUnlockableAmounts(address token, address denominator, uint256 amountToken, uint256 amountDenominator) external returns (uint256 unlockableToken, uint256 unlockableDenominator);
  function getCurrentWeekTimestamp() external view returns (uint256 currentWeek);
  function getLoanableAmount(address token, uint256 lockExpiration) external returns (uint256 loanableAmount);
  function getWritableAmount(address token, uint256 lockExpiration) external view returns (uint256 writableAmount);
  function getEquivalentCollateral(address token, uint256 amount, address collateralToken) external returns (uint256 collateralRequired);

  function deposit(address token, address denominator, uint256 amountToken, uint256 amountDenominator, uint256 lockExpiration) external;
  function withdraw(address token, address denominator, uint256 amountToken, uint256 amountDenominator) external;
  function borrow(address token, uint256 amountToken, address collateralToken, uint256 amountCollateral, uint256 lockExpiration) external;
  function repayLoan(Loan memory loan, uint256 amount) external;
  function liquidateLoan(bytes32 hash, uint256 amount, IUniswapV2Router02 router) external;
  function checkCollateralizationLevel(Loan memory loan) external returns (bool isCollateralized);
  function liquidate(bytes32 hash, uint256 collateralAmount, IUniswapV2Router02 router) external;
  function writeOption(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium, address referrer) external;
  function writeOptionFor(address receiver, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium, address referrer) external;
  function unwindOption(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium) external;
  function unwindOptionFor(address sender, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium) external;
  function unlockCollateralFromOption(address optionContract, uint256 optionId, uint256 amount) external;
}