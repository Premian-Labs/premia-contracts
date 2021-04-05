// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import '../interface/IPremiaOption.sol';
import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPriceOracleGetter.sol';
import '../interface/ILendingRateOracleGetter.sol';
import "../interface/IPremiaAMM.sol";
import "../interface/IPoolControllerChild.sol";
import '../uniswapV2/interfaces/IUniswapV2Router02.sol';

contract PremiaLiquidityPool is Ownable, ReentrancyGuard, IPoolControllerChild {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

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

    // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
    uint256 private constant _baseExpiration = 172799;
    // Expiration increment
    uint256 private constant _expirationIncrement = 1 weeks;
    // Max expiration time from now
    uint256 private _maxExpiration = 365 days;

    // Required collateralization level
    uint256 public requiredCollateralizationPercent = 1e4;    // 10000 = 100% collateralized
    // Max percent of collateral liquidated in a single liquidation event
    uint256 public maxPercentLiquidated = 5e3;    // 5000 = 50% of collateral
    // Max percent of capital allowed to be loaned in a single borrow event
    uint256 public maxLoanPercent = 5e3;    // 5000 = 50% of capital

    // Fee rewarded to successful callers of the liquidate function
    uint256 public liquidatorReward = 10;    // 10 = 0.1% fee
    // Max fee rewarded to successful callers of the liquidate function
    uint256 public maxLiquidatorReward = 2500;    // 2500 = 25% fee

    // Fee rewarded to successful callers of the unlockCollateral function
    uint256 public unlockReward = 10;    // 10 = 0.1% fee

    uint256 constant _inverseBasisPoint = 1e4;
    uint256 private constant WAD = 1e18;
    uint256 private constant WAD_RAY_RATIO = 1e9;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    IPremiaAMM public controller;
    IPriceOracleGetter public priceOracle;
    ILendingRateOracleGetter public lendingRateOracle;

    // Mapping of addresses with special permissions (Contracts who can borrow / write or whitelisted routers / tokens)
    mapping(address => Permissions) public permissions;

    // ToDo : Add optionContract to mapping ?

    // User -> Token -> Denominator -> Expiration -> UserInfo
    mapping(address => mapping(address => mapping(address => mapping (uint256 => UserInfo)))) public userInfos;

    // User -> Token -> Denominator -> Last unlock
    mapping(address => mapping(address => mapping(address => uint256))) public userLastUnlock;

    // Token -> Denominator -> Expiration -> UserInfo
    mapping(address => mapping(address => mapping(uint256 => PoolInfo))) public poolInfos;

    // ToDo : Remove / refactor this to work with new token/denom storage
    // Token -> Denominator -> Expiration -> Amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public amountsLockedByExpirationPerToken;

    // optionContract => optionId => amountTokenOutstanding
    mapping(address => mapping(uint256 => uint256)) public optionsOutstanding;

    ////////
    ////////

    // Max stake length multiplier
    uint256 public constant maxScoreMultiplier = 1e5; // 100% bonus if max stake length

    ////////
    ////////

    // Token -> amount
    mapping (address => uint256) public totalTokenDeposit;

        
    // hash => Loan
    mapping(bytes32 => Loan) public loans;

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

    constructor(IPremiaAMM _controller, IPriceOracleGetter _priceOracle, ILendingRateOracleGetter _lendingRateOracle) {
        controller = _controller;
        priceOracle = _priceOracle;
        lendingRateOracle = _lendingRateOracle;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyController() {
        require(msg.sender == address(controller), "Caller is not the controller");
        _;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    function upgradeController(address _newController) external override {
        require(msg.sender == owner() || msg.sender == address(controller), "Not owner or controller");
        controller = IPremiaAMM(_newController);
        emit ControllerUpdated(_newController);
    }


    function setPermissions(address[] memory _addr, Permissions[] memory _permissions) external onlyOwner {
        require(_addr.length == _permissions.length, "Arrays diff length");

        for (uint256 i=0; i < _addr.length; i++) {
            permissions[_addr[i]] = _permissions[i];

            emit PermissionsUpdated(_addr[i],
                _permissions[i].canBorrow,
                _permissions[i].isWhitelistedToken,
                _permissions[i].isWhitelistedOptionContract);
        }
    }

    /// @notice Set a new max expiration date for options writing (By default, 1 year from current date)
    /// @param _max The max amount of seconds in the future for which an option expiration can be set
    function setMaxExpiration(uint256 _max) external onlyOwner {
        _maxExpiration = _max;
    }

    /// @notice Set a new liquidator reward
    /// @param _reward New reward
    function setLiquidatorReward(uint256 _reward) external onlyOwner {
        require(_reward <= maxLiquidatorReward);
        liquidatorReward = _reward;
    }

    /// @notice Set a new max percent liquidated
    /// @param _maxPercent New max percent
    function setMaxPercentLiquidated(uint256 _maxPercent) external onlyOwner {
        require(_maxPercent <= _inverseBasisPoint);
        maxPercentLiquidated = _maxPercent;
    }

    /// @notice Set a new max loan percent
    /// @param _maxPercent New max percent
    function setMaxLoanPercent(uint256 _maxPercent) external onlyOwner {
        require(_maxPercent <= _inverseBasisPoint);
        maxLoanPercent = _maxPercent;
    }

    /// @notice Set the address of the oracle used for getting on-chain prices
    /// @param _priceOracleAddress The address of the oracle
    function setPriceOracle(address _priceOracleAddress) external onlyOwner {
        priceOracle = IPriceOracleGetter(_priceOracleAddress);
    }

    /// @notice Set the address of the oracle used for getting on-chain lending rates
    /// @param _lendingRateOracleAddress The address of the oracle
    function setLendingRateOracle(address _lendingRateOracleAddress) external onlyOwner {
        lendingRateOracle = ILendingRateOracleGetter(_lendingRateOracleAddress);
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    function _getNextExpiration() internal view returns (uint256) {
        uint256 nextExpiration = ((block.timestamp / _expirationIncrement) * _expirationIncrement) + _baseExpiration;
        if (nextExpiration < block.timestamp) {
            nextExpiration += _expirationIncrement;
        }

        return nextExpiration;
    }
    
    function getUnwritableAmount(address _optionContract, uint256 _optionId) public view returns (uint256) {
        return optionsOutstanding[_optionContract][_optionId];
    }

    function getWritableAmount(TokenPair memory _pair, uint256 _lockExpiration) public view returns (uint256) {
        uint256 expiration = _getNextExpiration();

        if (expiration < _lockExpiration) {
            expiration = _lockExpiration;
        }

        uint256 writableAmount;
        while (expiration <= block.timestamp + _maxExpiration) {
            PoolInfo memory pInfo = poolInfos[_pair.token][_pair.denominator][expiration];

            if (_pair.useToken) {
                writableAmount += pInfo.tokenAmount;
            } else {
                writableAmount += pInfo.denominatorAmount;
            }

            expiration += _expirationIncrement;
        }

        return writableAmount;
    }

    /// @notice More gas efficient than getWritableAmount, as it stops iteration if amount required is reached
    function hasWritableAmount(address _token, address _denominator, uint256 _lockExpiration, uint256 _amount) public view returns(bool) {
        uint256 expiration = _getNextExpiration();

        if (expiration < _lockExpiration) {
            expiration = _lockExpiration;
        }

        uint256 writableAmount;
        while (expiration <= block.timestamp + _maxExpiration) {
            writableAmount += amountsLockedByExpirationPerToken[_token][_denominator][expiration];
            expiration += _expirationIncrement;

            if (writableAmount >= _amount) return true;
        }

        return false;
    }

    function getUnlockableAmount(address _user, address _token, address _denominator) external view returns (uint256 _tokenAmount, uint256 _denominatorAmount) {
        require(_token != _denominator, "Token = Denominator");

        uint256 lastUnlock = userLastUnlock[_user][_token][_denominator];

        // If 0, no deposits has ever been made
        if (lastUnlock == 0) return (0,0);

        uint256 expiration = ((lastUnlock / _expirationIncrement) * _expirationIncrement) + _baseExpiration;

        uint256 unlockableTokenAmount;
        uint256 unlockableDenominatorAmount;

        while (expiration < block.timestamp) {
            UserInfo memory uInfo = userInfos[msg.sender][_token][_denominator][expiration];

            unlockableTokenAmount += uInfo.tokenAmount;
            unlockableDenominatorAmount += uInfo.denominatorAmount;
            expiration += _expirationIncrement;
        }

        return (unlockableTokenAmount, unlockableDenominatorAmount);
    }

    //////////////////////////////////////////////////

    /// @notice Get the hash of an loan
    /// @param _loan The loan from which to calculate the hash
    /// @return The loan hash
    function getLoanHash(Loan memory _loan) public pure returns(bytes32) {
        return keccak256(abi.encode(_loan));
    }

    function _getLoanPool(address _token, address _denominator, uint256 _expiration, bool _isCall, uint256 _amount) internal view returns (IPremiaLiquidityPool) {
        // Call borrow from put pools / Put borrows from call pools
        IPremiaLiquidityPool[] memory liquidityPools = _isCall ? controller.getPutPools() : controller.getCallPools();

        for (uint256 i = 0; i < liquidityPools.length; i++) {
            IPremiaLiquidityPool pool = liquidityPools[i];
            IPremiaLiquidityPool.TokenPair memory pair = IPremiaLiquidityPool.TokenPair({token: _token, denominator: _denominator, useToken: _isCall});
            uint256 amountAvailable = pool.getLoanableAmount(pair, _expiration);

            if (amountAvailable >= _amount) {
                return pool;
            }
        }

        revert("Not enough liquidity");
    }

    function _getAmountToBorrow(uint256 _amount, address collateralToken, address tokenToBorrow) internal view returns (uint256) {
        uint256 priceOfCollateral = priceOracle.getAssetPrice(collateralToken);
        uint256 priceOfBorrowed = priceOracle.getAssetPrice(tokenToBorrow);
        // ToDo : Do we wanna add ability to modify the 0.3% fee ?
        return (_amount * _inverseBasisPoint / 9970) * priceOfCollateral / priceOfBorrowed;
    }

    function getLoanableAmount(TokenPair memory _pair, uint256 _lockExpiration) public view virtual returns (uint256) {
        uint256 writableAmount = getWritableAmount(_pair, _lockExpiration);
        return writableAmount * _inverseBasisPoint / maxLoanPercent;
    }

    function getRequiredCollateralToBorrowLoan(Loan memory _loan) public view returns (uint256) {
        uint256 expectedTime = _loan.lockExpiration - _loan.creationTime;

        // ToDo : Extract in an internal function as it is used at multiple places ?
        address collateralToken;
        uint256 tokenBorrowedPrice;
        uint256 collateralPrice;

        if (_loan.borrowToken) {
            collateralToken = _loan.denominator;
            tokenBorrowedPrice = _loan.tokenPrice;
            collateralPrice = _loan.denominatorPrice;
        } else {
            collateralToken = _loan.token;
            tokenBorrowedPrice = _loan.denominatorPrice;
            collateralPrice = _loan.tokenPrice;
        }

        return getRequiredCollateral(collateralToken,
                                     tokenBorrowedPrice,
                                     collateralPrice,
                                     _loan.amountBorrow,
                                     _loan.lendingRate,
                                     expectedTime);
    }

    function getRequiredCollateralToRepayLoan(Loan memory _loan, uint256 _amount) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - _loan.creationTime;

        address collateralToken;
        uint256 tokenBorrowedPrice;
        uint256 collateralPrice;

        if (_loan.borrowToken) {
            collateralToken = _loan.denominator;
            tokenBorrowedPrice = _loan.tokenPrice;
            collateralPrice = _loan.denominatorPrice;
        } else {
            collateralToken = _loan.token;
            tokenBorrowedPrice = _loan.denominatorPrice;
            collateralPrice = _loan.tokenPrice;
        }

        return getRequiredCollateral(collateralToken,
                                     tokenBorrowedPrice,
                                     collateralPrice,
                                     _loan.amountBorrow,
                                     _loan.lendingRate,
                                     timeElapsed);
    }

    function getRequiredCollateral(address _collateralToken,
                                   uint256 _tokenPrice,
                                   uint256 _collateralPrice,
                                   uint256 _amount,
                                   uint256 _lendingRate,
                                   uint256 _loanLengthInSeconds) public view returns (uint256) {
        uint256 equivalentCollateral = (_amount * _tokenPrice) / _collateralPrice;
        uint256 ltvRatio = controller.loanToValueRatios(_collateralToken);
        uint256 expectedCompoundInterest = calculateCompoundInterest(_lendingRate, _loanLengthInSeconds);
        return (equivalentCollateral * _inverseBasisPoint / ltvRatio) + expectedCompoundInterest;
    }

    function isLoanUnderCollateralized(Loan memory _loan) public view returns (bool) {
        address collateralToken = _loan.borrowToken ? _loan.denominator : _loan.token;

        uint256 collateralPrice = priceOracle.getAssetPrice(collateralToken);
        uint256 percentCollateralized = (_loan.amountCollateral * collateralPrice * _inverseBasisPoint) / (_loan.amountBorrow * _loan.tokenPrice);
        return percentCollateralized < requiredCollateralizationPercent;
    }

    /**
    * @dev function to calculate the interest using a compounded interest rate formula
    * @param _rate the interest rate
    * @param _expiration the timestamp of the expiration of the loan
    * @return the interest rate compounded during the timeDelta
    **/
    function calculateExpectedCompoundInterest(uint256 _rate, uint256 _expiration) external view returns (uint256) {
        uint256 timeDifference = _expiration - block.timestamp;
        return calculateCompoundInterest(_rate, timeDifference);
    }

    /**
    * @dev function to calculate the interest using a compounded interest rate formula
    * @param _rate the interest rate
    * @param _loanCreationDate the timestamp the loan was created
    * @return the interest rate compounded during the timeDelta
    **/
    function calculateRealizedCompoundInterest(uint256 _rate, uint256 _loanCreationDate) external view returns (uint256) {
        uint256 timeDifference = block.timestamp - _loanCreationDate;
        return calculateCompoundInterest(_rate, timeDifference);
    }

    /**
    * @dev function to calculate the interest using a compounded interest rate formula
    * @param _rate the interest rate
    * @param _loanLengthInSeconds the length of the loan in seconds
    * @return the interest rate compounded during the timeDelta
    **/
    function calculateCompoundInterest(uint256 _rate, uint256 _loanLengthInSeconds) public view returns (uint256) {
        uint256 ratePerSecond = _rate / SECONDS_PER_YEAR;
        return ratePerSecond + (WAD ** _loanLengthInSeconds);
    }

    function _rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = WAD_RAY_RATIO / 2;
        return (halfRatio + a) / WAD_RAY_RATIO;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    function _unlockExpired(address _user, address _token, address _denominator) internal returns(uint256 _unlockedToken, uint256 _unlockedDenominator) {
        uint256 unlockedUntil = userLastUnlock[_user][_token][_denominator];

        // If 0, no deposits has ever been made
        if (unlockedUntil == 0) return (0, 0);

        uint256 expiration = ((unlockedUntil / _expirationIncrement) * _expirationIncrement) + _baseExpiration;

        uint256 unlockedToken;
        uint256 unlockedDenominator;

        while (expiration < block.timestamp) {
            UserInfo storage uInfo = userInfos[_user][_token][_denominator][expiration];

            // ToDo : What can we clean from UserInfo ?
            // delete userInfos[_user][_depositToken][_pairedToken][expiration];

            amountsLockedByExpirationPerToken[_token][_denominator][expiration] -= uInfo.tokenAmount;
            unlockedToken += uInfo.tokenAmount;
            unlockedDenominator += uInfo.denominatorAmount;
            expiration += _expirationIncrement;
        }

        userLastUnlock[_user][_token][_denominator] = block.timestamp;

        return (unlockedToken, unlockedDenominator);
    }

    function depositFrom(address _from, TokenPair[] memory _pairs, uint256[] memory _amounts, uint256 _lockExpiration) external onlyController nonReentrant {
        require(_pairs.length == _amounts.length, "Arrays diff length");
        require(_lockExpiration > block.timestamp, "Exp passed");
        require(_lockExpiration - block.timestamp <= _maxExpiration, "Exp > max exp");
        require(_lockExpiration % _expirationIncrement == _baseExpiration, "Wrong exp incr");

        for (uint256 i = 0; i < _pairs.length; i++) {
            address tokenDeposit = _pairs[i].useToken ? _pairs[i].token : _pairs[i].denominator;

            require(permissions[tokenDeposit].isWhitelistedToken, "Token not whitelisted");

            if (_amounts[i] == 0) continue;

            IERC20(tokenDeposit).safeTransferFrom(_from, address(this), _amounts[i]);

            address token = _pairs[i].token;
            address denominator = _pairs[i].denominator;

            UserInfo storage uInfo = userInfos[_from][token][denominator][_lockExpiration];
            PoolInfo storage pInfo = poolInfos[token][denominator][_lockExpiration];

            if (_pairs[i].useToken) {
                pInfo.tokenAmount += _amounts[i];
            } else {
                pInfo.denominatorAmount += _amounts[i];
            }

            uint256 multiplier = _inverseBasisPoint + ((_lockExpiration - block.timestamp) * maxScoreMultiplier / _maxExpiration);

            if (_pairs[i].useToken) {
                uInfo.tokenAmount += _amounts[i];
                uInfo.tokenScore += _amounts[i] * multiplier / _inverseBasisPoint;
            } else {
                uInfo.denominatorAmount += _amounts[i];
                uInfo.denominatorScore += _amounts[i] * multiplier / _inverseBasisPoint;
            }


            // If this is the first deposit ever made by this user, for this token
            if (userLastUnlock[_from][token][denominator] == 0) {
                userLastUnlock[_from][token][denominator] = block.timestamp;
            }

            // ToDo : Improve
            emit Deposit(_from, tokenDeposit, _lockExpiration, _amounts[i]);
        }
    }

    function withdrawExpiredFrom(address _from, TokenPair[] memory _pairs) external onlyController nonReentrant {
        for (uint256 i = 0; i < _pairs.length; i++) {
            (uint256 tokenAmount, uint256 denominatorAmount) = _unlockExpired(_from, _pairs[i].token, _pairs[i].denominator);

            if (tokenAmount > 0) {
                IERC20(_pairs[i].token).safeTransfer(_from, tokenAmount);
                emit Withdraw(_from, _pairs[i].token, tokenAmount);
            }

            if (denominatorAmount > 0) {
                IERC20(_pairs[i].denominator).safeTransfer(_from, denominatorAmount);
                emit Withdraw(_from, _pairs[i].denominator, denominatorAmount);
            }
        }
    }

    // ToDo : Review this
    function _subtractLockedAmounts(TokenPair memory _pair, uint256 _lockExpiration, uint256 _amount) internal {
        uint256 expiration = _lockExpiration;
        uint256 amountLeft = _amount;


        while (amountLeft > 0 && expiration <= block.timestamp + _maxExpiration) {
            PoolInfo storage pInfo = poolInfos[_pair.token][_pair.denominator][_lockExpiration];

            uint256 amountLocked;

            if (_pair.useToken) {
                amountLocked = pInfo.tokenAmount;

                if (amountLocked > amountLeft) {
                    pInfo.tokenAmount -= amountLeft;
                    return;
                } else {
                    pInfo.tokenAmount = 0;
                    amountLeft -= amountLocked;
                }

            } else {
                amountLocked = pInfo.denominatorAmount;

                if (amountLocked > amountLeft) {
                    pInfo.denominatorAmount -= amountLeft;
                    return;
                } else {
                    pInfo.denominatorAmount = 0;
                    amountLeft -= amountLocked;
                }
            }

            expiration += _expirationIncrement;
        }

        if (amountLeft > 0)
            revert();
    }

    function _lendCapital(Loan memory _loan) internal {
        TokenPair memory pair = TokenPair({token: _loan.token, denominator: _loan.denominator, useToken: _loan.borrowToken});
        uint256 loanableAmount = getLoanableAmount(pair, _loan.lockExpiration);
        uint256 collateralRequired = getRequiredCollateralToBorrowLoan(_loan);

        require(loanableAmount >= _loan.amountBorrow, "Amount too high.");
        require(collateralRequired <= _loan.amountCollateral, "Not enough collateral.");

        _subtractLockedAmounts(pair, _loan.lockExpiration, _loan.amountBorrow);

        UserInfo storage uInfo = userInfos[msg.sender][_loan.token][_loan.denominator][_loan.lockExpiration];
        PoolInfo storage pInfo = poolInfos[_loan.token][_loan.denominator][_loan.lockExpiration];

        if (_loan.borrowToken) {
            pInfo.denominatorAmount += _loan.amountCollateral;
            uInfo.denominatorAmount += _loan.amountCollateral;

            IERC20(_loan.denominator).safeTransferFrom(msg.sender, address(this), _loan.amountCollateral);
            IERC20(_loan.token).safeTransfer(msg.sender, _loan.amountBorrow);
        } else {
            pInfo.tokenAmount += _loan.amountCollateral;
            uInfo.tokenAmount += _loan.amountCollateral;

            IERC20(_loan.token).safeTransferFrom(msg.sender, address(this), _loan.amountCollateral);
            IERC20(_loan.denominator).safeTransfer(msg.sender, _loan.amountBorrow);
        }

        bytes32 hash = getLoanHash(_loan);
        loans[hash] = _loan;

        emit Borrow(hash, msg.sender, _loan.token, _loan.denominator, _loan.borrowToken, _loan.lockExpiration, _loan.amountBorrow, _loan.amountCollateral, _loan.lendingRate);
    }

    function borrow(TokenPair memory _pair, uint256 _amountBorrow, uint256 _amountCollateral, uint256 _lockExpiration) external nonReentrant returns (Loan memory) {
        bool borrowToken = _pair.useToken;
        address collateralToken = borrowToken ? _pair.denominator : _pair.token;

        require(controller.loanToValueRatios(collateralToken) > 0, "Collateral token not allowed.");
        require(permissions[msg.sender].canBorrow, "Borrow not whitelisted.");

        uint256 tokenPrice = priceOracle.getAssetPrice(_pair.token);
        uint256 denominatorPrice = priceOracle.getAssetPrice(_pair.denominator);
        // ToDo : Check this
        uint256 lendingRate = _rayToWad(lendingRateOracle.getMarketBorrowRate(_pair.token));


        Loan memory loan = Loan(address(this),
                                msg.sender,
                                _pair.token,
                                _pair.denominator,
                                borrowToken,
                                _amountBorrow,
                                _amountCollateral,
                                block.timestamp,
                                _lockExpiration,
                                tokenPrice,
                                denominatorPrice,
                                lendingRate);

        _lendCapital(loan);

        return loan;
    }

    function repayLoan(Loan memory _loan, uint256 _amount) external returns (uint256) {
        bytes32 hash = getLoanHash(_loan);
        return repay(hash, _amount);
    }

    // ToDo : Review / fix this
    function repay(bytes32 _hash, uint256 _amount) public nonReentrant returns (uint256) {
        Loan storage loan = loans[_hash];

        uint256 collateralOut = getRequiredCollateralToRepayLoan(loan, _amount);

        UserInfo storage uInfo = userInfos[loan.borrower][loan.token][loan.denominator][loan.lockExpiration];

        address borrowedToken = loan.borrowToken ? loan.token : loan.denominator;
        address collateralToken = loan.borrowToken ? loan.denominator : loan.token;
        uint256 collateralAmount = loan.borrowToken ? uInfo.denominatorAmount : uInfo.tokenAmount;

        require(collateralAmount >= collateralOut, "Not enough collateral.");

        IERC20(borrowedToken).safeTransferFrom(msg.sender, address(this), _amount);

        loan.amountBorrow -= _amount;

//        if (loan.amountBorrow == 0) {
//            collateralOut = loan.amountCollateral;
//
//            // ToDo : Cleanup ?
//            delete loans[_hash];
//        }

        loan.amountCollateral -= collateralOut;

        PoolInfo storage pInfo = poolInfos[loan.token][loan.denominator][loan.lockExpiration];
        if (loan.borrowToken) {
            pInfo.denominatorAmount -= collateralOut;
            uInfo.denominatorAmount -= collateralOut;
        } else {
            pInfo.tokenAmount -= collateralOut;
            uInfo.tokenAmount -= collateralOut;
        }

        IERC20(collateralToken).safeTransfer(loan.borrower, collateralOut);

        // ToDo : Fix
        emit RepayLoan(_hash, msg.sender, loan.token, _amount);

        return collateralOut;
    }

    /// @notice Convert collateral back into original tokens
    /// @param _inputToken The token to swap from
    /// @param _outputToken The token to swap to
    /// @param _amountIn The amount of _inputToken to swap
    function _swapTokensIn(address _inputToken, address _outputToken, uint256 _amountIn) internal returns (uint256) {
        IUniswapV2Router02 router = controller.getDesignatedSwapRouter(_inputToken, _outputToken);

        IERC20(_inputToken).safeIncreaseAllowance(address(router), _amountIn);

        address weth = router.WETH();
        address[] memory path = controller.customSwapPaths(_inputToken, _outputToken);

        if (path.length == 0) {
            path = new address[](2);
            path[0] = _inputToken;
            path[1] = weth;
        }

        path[path.length] = _outputToken;

        uint256[] memory amounts = router.swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            block.timestamp + 60
        );

        return amounts[1];
    }

    /// @notice Convert collateral back into original tokens
    /// @param _collateralToken The token to swap from
    /// @param _token The token to swap collateral to
    /// @param _amountCollateral The amount of collateral
    function _liquidateCollateral(address _collateralToken, address _token, uint256 _amountCollateral) internal returns (uint256) {
        return _swapTokensIn(_collateralToken, _token, _amountCollateral);
    }

    function _postLiquidate(Loan memory loan, uint256 _collateralAmount) virtual internal {}

    function liquidateLoan(Loan memory _loan, uint256 _amount) external {
        bytes32 hash = getLoanHash(_loan);
        liquidate(hash, _amount);
    }

    function liquidate(bytes32 _hash, uint256 _collateralAmount) public nonReentrant {
        Loan storage loan = loans[_hash];

        address collateralToken = loan.borrowToken ? loan.denominator : loan.token;

        require(loan.amountCollateral * _inverseBasisPoint / _collateralAmount >= maxPercentLiquidated, "Too much liquidated.");
        require(isLoanUnderCollateralized(loan) ||    loan.lockExpiration < block.timestamp, "Loan cannot be liquidated.");

        uint256 amountToken = _liquidateCollateral(collateralToken, loan.token, _collateralAmount);

        loan.amountBorrow -= amountToken;
        loan.amountCollateral -= _collateralAmount;

        UserInfo storage uInfo = userInfos[loan.borrower][loan.token][loan.denominator][loan.lockExpiration];
        PoolInfo storage pInfo = poolInfos[loan.token][loan.denominator][loan.lockExpiration];

        if (loan.borrowToken) {
            uInfo.denominatorAmount -= _collateralAmount;
            pInfo.denominatorAmount -= _collateralAmount;
        } else {
            uInfo.tokenAmount -= _collateralAmount;
            pInfo.tokenAmount -= _collateralAmount;
        }

        // ToDo : Account for loss

        _postLiquidate(loan, _collateralAmount);

        uint256 rewardFee = (amountToken * _inverseBasisPoint) / liquidatorReward;

        IERC20(collateralToken).safeTransfer(msg.sender, rewardFee);

        if (loan.amountCollateral == 0) {
            delete loans[_hash];
        }

        // Fix this
        emit LiquidateLoan(_hash, msg.sender, loan.token, _collateralAmount, rewardFee);
    }

    function buyOption(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium, address _referrer) public nonReentrant onlyController {
        require(permissions[_optionContract].isWhitelistedOptionContract, "Option contract not whitelisted.");

        IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);

        address denominator = IPremiaOption(_optionContract).denominator();

        PoolInfo storage pInfo = poolInfos[data.token][denominator][data.expiration];

        IERC20(denominator).safeTransferFrom(msg.sender, address(this), _amountPremium);
        pInfo.tokenPnl += _amountPremium.toInt256();

        optionsOutstanding[_optionContract][_optionId] += _amount;

        IPremiaOption.OptionWriteArgs memory writeArgs = IPremiaOption.OptionWriteArgs({
                amount: _amount,
                token: data.token,
                strikePrice: data.strikePrice,
                expiration: data.expiration,
                isCall: data.isCall
        });

        TokenPair memory pair = TokenPair({token: data.token, denominator: denominator, useToken: data.isCall});
        _subtractLockedAmounts(pair, data.expiration, _amount);

        IPremiaOption(_optionContract).writeOption(data.token, writeArgs, _referrer);
        IPremiaOption(_optionContract).safeTransferFrom(address(this), _receiver, _optionId, _amount, "");

        _afterBuyOption(_receiver, _optionContract, _optionId, _amount, _amountPremium, _referrer);

        emit BoughtOption(_receiver, msg.sender, _optionContract, _optionId, _amount, denominator, _amountPremium);
    }

    function _afterBuyOption(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium, address _referrer) internal virtual {}

    // ToDo: _amount not used in any override, can we remove it ?
    function _afterSellOption(address _optionContract, uint256 _optionId, uint256 _amount, uint256 _tokenWithdrawn, uint256 _denominatorWithdrawn) virtual internal {}

    function sellOption(address _sender, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium) public nonReentrant onlyController {
        require(permissions[_optionContract].isWhitelistedOptionContract, "Option contract not whitelisted.");
        require(optionsOutstanding[_optionContract][_optionId] >= _amount, "Not enough written.");

        IPremiaOption optionContract = IPremiaOption(_optionContract);
        IPremiaOption.OptionData memory data = optionContract.optionData(_optionId);

        address denominator = optionContract.denominator();
        uint256 preTokenBalance = IERC20(data.token).balanceOf(address(this));
        uint256 preDenominatorBalance = IERC20(denominator).balanceOf(address(this));

        optionsOutstanding[_optionContract][_optionId] -= _amount;

        // ToDo : The expired case should be treated separately, so that this function can be more gas efficient
        if (data.expiration < block.timestamp) {
            IPremiaOption(_optionContract).withdraw(_optionId);
        } else {
            IPremiaOption(_optionContract).cancelOption(_optionId, _amount);
        }

        uint256 tokenWithdrawn = IERC20(data.token).balanceOf(address(this)) - preTokenBalance;
        uint256 denominatorWithdrawn = IERC20(denominator).balanceOf(address(this)) - preDenominatorBalance;
        
        // TODO: the following should probably not use `date.expiration`, but rather the original date the amount
        // was locked until. However, it is not possible to save this amount, for each trade.
        // It may be possible to store an average over all trades in a specific option id, but this won't
        // be entirely accurate either.
        //
        // The following situation shows the issue:
        // IF `data.expiration` is used:
        // User A deposits Token A locked for 1 Year.
        // User B immediately purchases call options of Token A, with expiration 1 week out, for the full amount deposited by User A.
        // 1 week later, User A's tokens are unlocked, but the user still cannot withdraw their tokens for 51 weeks
        // User A's tokens can no longer be used to write options on the market, and cannot be withdrawn for 51 weeks.

        PoolInfo storage pInfo = poolInfos[data.token][denominator][data.expiration];

        pInfo.tokenAmount -= tokenWithdrawn;
        pInfo.denominatorAmount -= denominatorWithdrawn;

        // ToDo : If denominatorPnl ends up negative, need to be repaid through swapping tokens
        pInfo.denominatorPnl -= _amountPremium.toInt256();
        IERC20(denominator).safeTransfer(_sender, _amountPremium);

        _afterSellOption(_optionContract, _optionId, _amount, tokenWithdrawn, denominatorWithdrawn);

        emit SoldOption(_sender, msg.sender, _optionContract, _optionId, _amount, denominator, _amountPremium);
    }

    function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) public nonReentrant {
        IPremiaOption optionContract = IPremiaOption(_optionContract);
        IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);

        require(data.expiration > block.timestamp, "Option is not expired yet.");
        require(permissions[_optionContract].isWhitelistedOptionContract, "Option contract not whitelisted.");
        require(optionsOutstanding[_optionContract][_optionId] >= _amount, "Not enough written.");

        address denominatorToken = optionContract.denominator();
        uint256 preTokenBalance = IERC20(data.token).balanceOf(address(this));
        uint256 preDenominatorBalance = IERC20(denominatorToken).balanceOf(address(this));

        optionsOutstanding[_optionContract][_optionId] -= _amount;

        IPremiaOption(_optionContract).withdraw(_optionId);

        uint256 tokenWithdrawn = IERC20(data.token).balanceOf(address(this)) - preTokenBalance;
        uint256 denominatorWithdrawn = IERC20(denominatorToken).balanceOf(address(this)) - preDenominatorBalance;

        uint256 tokenRewardFee = (tokenWithdrawn * _inverseBasisPoint) / unlockReward;
        uint256 denominatorRewardFee = (denominatorWithdrawn * _inverseBasisPoint) / unlockReward;

        uint256 tokenIncrease = tokenWithdrawn - tokenRewardFee;
        uint256 denominatorIncrease = denominatorWithdrawn - denominatorRewardFee;
        
        // TODO: the following should probably not use `date.expiration`, but rather the original date the amount
        // was locked until. However, it is not possible to save this amount, for each trade.
        // It may be possible to store an average over all trades in a specific option id, but this won't
        // be entirely accurate either.
        //
        // The following situation shows the issue:
        // IF `data.expiration` is used:
        // User A deposits Token A locked for 1 Year.
        // User B immediately purchases call options of Token A, with expiration 1 week out, for the full amount deposited by User A.
        // 1 week later, User A's tokens are unlocked, but the user still cannot withdraw their tokens for 51 weeks
        // User A's tokens can no longer be used to write options on the market, and cannot be withdrawn for 51 weeks.

        amountsLockedByExpirationPerToken[data.token][denominatorToken][data.expiration] += tokenIncrease;
        amountsLockedByExpirationPerToken[denominatorToken][data.token][data.expiration] += denominatorIncrease;
        
        if (tokenWithdrawn > 0 && denominatorWithdrawn > 0) {
            IERC20(data.token).safeTransfer(msg.sender, tokenRewardFee);
            IERC20(denominatorToken).safeTransfer(msg.sender, denominatorRewardFee);
        } else if (tokenWithdrawn > 0) {
            IERC20(data.token).safeTransfer(msg.sender, tokenRewardFee);
        } else {
            IERC20(denominatorToken).safeTransfer(msg.sender, denominatorRewardFee);
        }

        _afterSellOption(_optionContract, _optionId, _amount, tokenIncrease, denominatorIncrease);

        emit UnlockCollateral(msg.sender, _optionContract, _optionId, _amount, tokenRewardFee, denominatorRewardFee);
    }
}