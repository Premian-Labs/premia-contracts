// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import '../interface/IPriceOracleGetter.sol';
import "../uniswapV2/interfaces/IUniswapV2Router02.sol";

interface IPremiaLiquidityPool {
  struct Loan {
    address lender;
    address borrower;
    address token;
    address collateralToken;
    uint256 amountTokenOutstanding;
    uint256 amountCollateralTokenHeld;
    uint256 lockExpiration;
    uint256 tokenPrice;
    uint256 collateralPrice;
  }

  struct Permissions {
    bool canBorrow;
    bool canWrite;
    bool isWhitelistedToken;
  }

  function getWritableAmount(address _token, uint256 _lockExpiration) external view returns (uint256);
  function hasWritableAmount(address _token, uint256 _lockExpiration, uint256 _amount) external view returns(bool);
  function getUnlockableAmount(address _user, address _token) external view returns (uint256);
  function getLoanHash(Loan memory _loan) external pure returns(bytes32);
  function getLoanableAmount(address _token, uint256 _lockExpiration) external returns (uint256);
  function getEquivalentCollateral(address _token, uint256 _amount, address _collateralToken) external returns (uint256);
  function depositFrom(address _from, address[] memory _tokens, uint256[] memory _amounts, uint256 _lockExpiration) external;
  function withdrawExpiredFrom(address _from, address[] memory _tokens) external;
  function borrow(address _token, uint256 _amountToken, address _collateralToken, uint256 _amountCollateral, uint256 _lockExpiration) external returns (Loan memory);
  function repayLoan(Loan memory _loan, uint256 _amount) external returns (uint256);
  function repay(bytes32 _hash, uint256 _amount) external returns (uint256);
  function checkCollateralizationLevel(Loan memory _loan) external returns (bool);
  function liquidateLoan(Loan memory _loan, uint256 _amount) external;
  function liquidate(bytes32 _hash, uint256 _collateralAmount) external;
  function writeOption(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) external;
  function writeOptionFor(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) external;
  function unwindOption(address _optionContract, uint256 _optionId, uint256 _amount) external;
  function unwindOptionFor(address _sender, address _optionContract, uint256 _optionId, uint256 _amount) external;
  function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) external;
}