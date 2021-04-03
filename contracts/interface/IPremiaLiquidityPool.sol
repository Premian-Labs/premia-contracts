// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '../interface/IPriceOracleGetter.sol';
import '../interface/IPremiaOption.sol';
import "../uniswapV2/interfaces/IUniswapV2Router02.sol";

interface IPremiaLiquidityPool {
    struct Loan {
        address lender;
        address borrower;
        address token;
        address denominator;
        bool borrowToken; // If true, we are borrowing token, if false, we are borrowing denominator
        uint256 amountBorrow;
        uint256 amountCollateral;
        uint256 creationTime;
        uint256 lockExpiration;
        uint256 tokenPrice;
        uint256 denominatorPrice;
        uint256 lendingRate;
    }

    struct TokenPair {
        address token;
        address denominator;
        bool useToken; // If true, we are using token, if false, we are using denominator
    }

    ////////////
    // Events //
    ////////////

    event PermissionsUpdated(address indexed addr, bool canBorrow, bool isWhitelistedToken, bool isWhitelistedOptionContract);
    event Deposit(address indexed user, address indexed token,uint256 lockExpiration, uint256 amountToken);
    event Withdraw(address indexed user, address indexed token, uint256 amountToken);
    event Borrow(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed lockExpiration, uint256 amount, uint256 lendingRate);
    event RepayLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount);
    event LiquidateLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount, uint256 rewardFee);
    event BoughtOption(address indexed receiver, address indexed writer, address indexed optionContract, uint256 optionId, uint256 amount, uint256 amountPremium);
    event SoldOption(address indexed sender, address indexed writer, address indexed optionContract, uint256 optionId, uint256 amount, uint256 amountPremium);
    event UnlockCollateral(address indexed unlocker, address indexed optionContract, uint256 indexed optionId, uint256 amount, uint256 tokenRewardFee, uint256 denominatorRewardFee);
    event ControllerUpdated(address indexed newController);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    function upgradeController(address _newController) external;

    function getUnwritableAmount(address _optionContract, uint256 _optionId) external view returns (uint256);
    function getWritableAmount(address _token, uint256 _lockExpiration) external view returns (uint256);
    function hasWritableAmount(address _token, uint256 _lockExpiration, uint256 _amount) external view returns(bool);
    function getUnlockableAmount(address _user, address _token) external view returns (uint256);
    function getLoanHash(Loan memory _loan) external pure returns(bytes32);
    function getLoanableAmount(address _token, uint256 _lockExpiration) external returns (uint256);
    function getEquivalentCollateral(uint256 _tokenPrice, uint256 _collateralPrice, uint256 _amount) external view returns (uint256);
    function getEquivalentCollateralForLoan(Loan memory _loan, uint256 _amount) external view returns (uint256);
    function getRequiredCollateral(address _collateralToken, uint256 _tokenPrice, uint256 _collateralPrice, uint256 _amount) external view returns (uint256);
    function getRequiredCollateralForLoan(Loan memory _loan, uint256 _amount) external view returns (uint256);

    function depositFrom(address _from, address[] memory _tokens, uint256[] memory _amounts, uint256 _lockExpiration) external;
    function withdrawExpiredFrom(address _from, address[] memory _tokens) external;
    function borrow(TokenPair memory _pair, uint256 _amountBorrow, uint256 _amountCollateral, uint256 _lockExpiration) external returns (Loan memory);
    function repayLoan(Loan memory _loan, uint256 _amount) external returns (uint256);
    function repay(bytes32 _hash, uint256 _amount) external returns (uint256);
    function isLoanUnderCollateralized(Loan memory _loan) external returns (bool);
    function isExpirationPast(Loan memory loan) external returns (bool);
    function liquidateLoan(Loan memory _loan, uint256 _amount) external;
    function liquidate(bytes32 _hash, uint256 _collateralAmount) external;
    function buyOption(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium, address _referrer) external;
    function sellOption(address _sender, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium) external;
    function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) external;
}