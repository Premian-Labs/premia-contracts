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

    struct Permissions {
        bool canBorrow;
        bool isWhitelistedToken;
        bool isWhitelistedOptionContract;
    }

    struct UserInfo {
        uint256 tokenAmount;
        uint256 denominatorAmount;

        uint256 tokenScore;
        uint256 denominatorScore;

        uint256 tokenPnlDebt;
        uint256 denominatorPnlDebt;

        uint256 lastUnlock; // Last timestamp at which deposits unlock was run. This is necessary so that we know from which timestamp we need to iterate, when unlocking
    }

    struct TokenPair {
        address token;
        address denominator;
        bool useToken; // If true, we are using token, if false, we are using denominator
    }

    struct PoolInfo {
        uint256 tokenAmount;
        uint256 denominatorAmount;

        int256 tokenPnl;
        int256 denominatorPnl;

        uint256[] optionIdList;
    }

    ////////////
    // Events //
    ////////////

    event PermissionsUpdated(address indexed addr, bool canBorrow, bool isWhitelistedToken, bool isWhitelistedOptionContract);
    event Deposit(address indexed user, address indexed token,uint256 lockExpiration, uint256 amountToken);
    event Withdraw(address indexed user, address indexed token, uint256 amountToken);
    event Borrow(bytes32 hash, address indexed borrower, address indexed token, address indexed denominator, bool borrowToken, uint256 lockExpiration, uint256 amountBorrow, uint256 amountCollateral, uint256 lendingRate);
    event RepayLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount);
    event LiquidateLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount, uint256 rewardFee);
    event BoughtOption(address indexed receiver, address indexed writer, address indexed optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium);
    event SoldOption(address indexed sender, address indexed writer, address indexed optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium);
    event UnlockCollateral(address indexed unlocker, address indexed optionContract, uint256 indexed optionId, uint256 amount, uint256 tokenRewardFee, uint256 denominatorRewardFee);
    event ControllerUpdated(address indexed newController);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    function upgradeController(address _newController) external;

    //////////
    // View //
    //////////

    function getUnwritableAmount(address _optionContract, uint256 _optionId) external view returns (uint256);
    function getWritableAmount(TokenPair memory _pair, uint256 _lockExpiration) external view returns (uint256);
    function hasWritableAmount(address _token, address _denominator, uint256 _lockExpiration, uint256 _amount) external view returns(bool);
    function getUnlockableAmount(address _user, address _token, address _denominator) external view returns (uint256 _tokenAmount, uint256 _denominatorAmount);
    function getLoanHash(Loan memory _loan) external pure returns(bytes32);
    function getLoanableAmount(TokenPair memory _pair, uint256 _lockExpiration) external view returns (uint256);
    function getRequiredCollateralToBorrowLoan(Loan memory _loan) external view returns (uint256);
    function getRequiredCollateralToRepayLoan(Loan memory _loan, uint256 _amount) external view returns (uint256);
    function isLoanUnderCollateralized(Loan memory _loan) external view returns (bool);
    function getRequiredCollateral(address _collateralToken, uint256 _tokenPrice, uint256 _collateralPrice, uint256 _amount, uint256 _lendingRate, uint256 _loanLengthInSeconds) external view returns (uint256);
    function calculateExpectedCompoundInterest(uint256 _rate, uint256 _expiration) external view returns (uint256);
    function calculateRealizedCompoundInterest(uint256 _rate, uint256 _loanCreationDate) external view returns (uint256);
    function calculateCompoundInterest(uint256 _rate, uint256 _loanLengthInSeconds) external view returns (uint256);

    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    function depositFrom(address _from, TokenPair[] memory _pairs, uint256[] memory _amounts, uint256 _lockExpiration) external;
    function withdrawExpiredFrom(address _from, TokenPair[] memory _pairs) external;
    function borrow(TokenPair memory _pair, uint256 _amountBorrow, uint256 _amountCollateral, uint256 _lockExpiration) external returns (Loan memory);
    function repayLoan(Loan memory _loan, uint256 _amount) external returns (uint256);
    function repay(bytes32 _hash, uint256 _amount) external returns (uint256);
    function liquidateLoan(Loan memory _loan, uint256 _amount) external;
    function liquidate(bytes32 _hash, uint256 _collateralAmount) external;
    function buyOption(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium, address _referrer) external;
    function sellOption(address _sender, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium) external;
    function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) external;
}