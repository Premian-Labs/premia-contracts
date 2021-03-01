// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';

import '../interface/IPriceOracleGetter.sol';

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

  // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
  uint256 public constant _baseExpiration = 172799;
  // Expiration increment
  uint256 public constant _expirationIncrement = 1 weeks;
  // Max expiration time from now
  uint256 public _maxExpiration;

  // Required collateralization level
  uint256 public _requiredCollaterizationPercent;  // 100 = 100% collateralized
  // Max percent of collateral liquidated in a single liquidation event
  uint256 public _maxPercentLiquidated;  // 500 = 50% of collateral

  // Fee rewarded to successful callers of the liquidate function
  uint256 public _liquidatorReward; // 10 = 0.1% fee
  // Max fee rewarded to successful callers of the liquidate function
  uint256 public constant _maxLiquidatorReward = 250;  // 250 = 25% fee
  uint256 public constant _inverseBasisPoint = 1000;

  // The oracle used to get prices on chain.
  IPriceOracleGetter public priceOracle;
  
  // List of whitelisted contracts that can borrow capital from this pool
  EnumerableSet.AddressSet private _whitelistedBorrowContracts;
  // List of whitelisted contracts that can write options from this pool
  EnumerableSet.AddressSet private _whitelistedWriterContracts;    
  // List of UniswapRouter contracts that can be used to swap tokens
  EnumerableSet.AddressSet private _whitelistedRouterContracts;

  // Set a custom swap path for a token
  mapping(address => mapping(address => address[])) public customSwapPaths;

  // user address => UserDeposit
  mapping(address => UserDeposit[]) public depositsByUser;
  // token => expiration => amount
  mapping(address => mapping(uint256 => uint256)) public amountsLockedByExpirationPerToken;
  
  // hash => loan
  mapping(bytes32 => Loan) public loansOutstanding;
  // optionContract => optionId => amountOutstanding
  mapping(address => mapping(uint256 => uint256)) public optionsOutstanding;

  event Deposit(address indexed user, address indexed token, address indexed denominator, uint256 indexed lockExpiration, uint256 amountToken, uint256 amountDenominator);
  event Withdraw(address indexed user, address indexed token, address indexed denominator, uint256 amountToken, uint256 amountDenominator);
  event Borrow(bytes32 indexed hash, address indexed borrower, address indexed token, uint256 indexed lockExpiration, uint256 amount);
  event RepayLoan(bytes32 indexed hash, address indexed borrower, address indexed token, uint256 indexed amount);
  event LiquidateLoan(bytes32 indexed hash, address indexed borrower, address indexed token, uint256 indexed amount, uint256 rewardFee);
  event WriteOption(address indexed writer, address indexed optionContract, uint256 indexed optionId, uint256 indexed amount, address premiumToken, uint256 amountPremium);
  event UnwindOption(address indexed writer, address indexed optionContract, uint256 indexed optionId, uint256 indexed amount);
  event UnlockCollateral(address indexed unlocker, address indexed optionContract, uint256 indexed optionId, uint256 indexed amount);

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
  
  function getLoanHash(Loan memory loan) public pure returns(bytes32);
  function getUnlockableAmounts(address token, address denominator, uint256 amountToken, uint256 amountDenominator) external returns (uint256 unlockableToken, uint256 unlockableDenominator);
  function getCurrentWeekTimestamp() public returns (uint256 currentWeek);
  function getLoanableAmount(address token, uint256 lockExpiration) public returns (uint256 loanableAmount);
  function getWritableAmount(address token, uint256 lockExpiration) public returns (uint256 writableAmount);
  function getEquivalentCollateral(address token, uint256 amount, address collateralToken) public returns (uint256 collateralRequired);

  function _unlockAmounts(address token, address denominator, uint256 amountToken, uint256 amountDenominator) internal;
  function deposit(address token, address denominator, uint256 amountToken, uint256 amountDenominator, uint256 lockExpiration) external;
  function withdraw(address token, address denominator, uint256 amountToken, uint256 amountDenominator) external;
  function borrow(address token, uint256 amountToken, address collateralToken, uint256 amountCollateral, uint256 lockExpiration) external;
  function repayLoan(Loan memory loan, uint256 amount) external;
  function liquidateLoan(bytes32 hash, uint256 amount) external;
  function checkCollateralizationLevel(Loan memory loan) public returns (bool isCollateralized);
  function _liquidateCollateral(IUniswapV2Router02 router, address collateralToken, address token, uint256 amountCollateral) internal;
  function liquidate(bytes32 hash, uint256 collateralAmount, address router) public;
  function writeOption(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium, address referrer) external;
  function writeOptionFor(address receiver, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium, address referrer) external;
  function unwindOption(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium) external;
  function unwindOptionFor(address sender, address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium) external;
  function unlockCollateralFromOption(address optionContract, uint256 optionId, uint256 amount) external;
}