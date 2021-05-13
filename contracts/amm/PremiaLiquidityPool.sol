// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import './AMMStruct.sol';
import '../interface/IERC20Extended.sol';
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
        bool isWhitelistedOptionContract;
    }

    struct OptionId {
        address contractAddress;
        uint256 optionId;
    }

    struct UserInfo {
        uint256 amount;
        uint256 score;

        int256 tokenPnlDebt;
        int256 denominatorPnlDebt;

        uint256 lastUnlock; // Last timestamp at which deposits unlock was run. This is necessary so that we know from which timestamp we need to iterate, when unlocking
    }

    struct PoolInfo {
        uint256 amount;
        uint256 amountLocked;

        int256 tokenPnl;
        int256 denominatorPnl;

        OptionId[] optionIdList;
    }

    // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
    uint256 private constant _baseExpiration = 172799;
    // Expiration increment
    uint256 private constant _expirationIncrement = 1 weeks;
    // Max expiration time from now of options from option contract (Same value as PremiaOption contract)
    uint256 private _maxExpiration = 365 days;

    // Limit initial max deposit length to 1 month, during beta. Will be increased later
    uint256 public maxDepositExpiration = 30 days;

    // If true, tokens are deposited into this pool, if false denominator is deposited into this pool
    bool public immutable isTokenPool;

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

    // Mapping of whitelisted pairs from which token can be deposited into the contract
    // Token -> Denominator -> isWhitelisted
    mapping(address => mapping(address => bool)) public whitelistedPairs;

    // Mapping of addresses with special permissions (Contracts who can borrow / write or whitelisted routers / tokens)
    mapping(address => Permissions) public permissions;

    // User -> Token -> Denominator -> Expiration -> UserInfo
    mapping(address => mapping(address => mapping(address => mapping (uint256 => UserInfo)))) public userInfos;

    // User -> Token -> Denominator -> Last unlock
    mapping(address => mapping(address => mapping(address => uint256))) public userLastUnlock;

    // Token -> Denominator -> Expiration -> PoolInfo
    mapping(address => mapping(address => mapping(uint256 => PoolInfo))) public poolInfos;

    // Oldest potential non-unwinded option in this pool
    // Token -> Denominator -> Timestamp of oldest outstanding option
    mapping(address => mapping(address => uint256)) public oldestOutstandingOption;

    // optionContract => optionId => amountTokenOutstanding
    mapping(address => mapping(uint256 => uint256)) public optionsOutstanding;

    ////////
    ////////

    // Max stake length multiplier
    uint256 public constant maxScoreMultiplier = 1e4; // 100% bonus if max stake length

    ////////
    ////////

    // Token -> amount
    mapping (address => uint256) public totalTokenDeposit;


    // hash => Loan
    mapping(bytes32 => Loan) public loans;

    ////////////
    // Events //
    ////////////

    event PairWhitelisted(address indexed token, address indexed denominator, bool state);
    event PermissionsUpdated(address indexed addr, bool canBorrow, bool isWhitelistedOptionContract);
    event Deposit(address indexed user, address indexed token, address indexed denominator, bool useToken, uint256 lockExpiration, uint256 amountToken);
    event Withdraw(address indexed user, address indexed token, address indexed denominator, bool useToken, uint256 amountToken);
    event Borrow(bytes32 hash, address indexed borrower, address indexed token, address indexed denominator, bool borrowToken, uint256 lockExpiration, uint256 amountBorrow, uint256 amountCollateral, uint256 lendingRate);
    event RepayLoan(bytes32 hash, address indexed borrower, address indexed token, address indexed denominator, bool borrowToken, uint256 amount);
    event LiquidateLoan(bytes32 hash, address indexed borrower, address indexed token, address indexed denominator, bool borrowToken, uint256 amount, uint256 rewardFee);
    event BoughtOption(address indexed from, address indexed optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium);
    event SoldOption(address indexed from, address indexed optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium);
    event UnwindedOption(address indexed optionContract, uint256 indexed optionId, uint256 amount);
    event UnlockCollateral(address indexed unlocker, address indexed optionContract, uint256 indexed optionId, uint256 amount, uint256 tokenRewardFee, uint256 denominatorRewardFee);
    event ControllerUpdated(address indexed newController);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(IPremiaAMM _controller, bool _isTokenPool, IPriceOracleGetter _priceOracle, ILendingRateOracleGetter _lendingRateOracle) {
        isTokenPool = _isTokenPool;
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

    function setWhitelistedPairs(AMMStruct.TokenPair[] memory _pairs, bool[] memory _states) external {
        require(msg.sender == owner() || msg.sender == address(controller), "Not owner or controller");
        require(_pairs.length == _states.length, "Arrays diff length");

        for (uint256 i=0; i < _pairs.length; i++) {
            whitelistedPairs[_pairs[i].token][_pairs[i].denominator] = _states[i];
            emit PairWhitelisted(_pairs[i].token, _pairs[i].denominator, _states[i]);
        }
    }

    function setPermissions(address[] memory _addr, Permissions[] memory _permissions) external {
        require(_addr.length == _permissions.length, "Arrays diff length");

        for (uint256 i=0; i < _addr.length; i++) {
            permissions[_addr[i]] = _permissions[i];

            emit PermissionsUpdated(_addr[i],
                _permissions[i].canBorrow,
                _permissions[i].isWhitelistedOptionContract);
        }
    }

    /// @notice Set a new max expiration date for options writing (By default, 1 year from current date)
    /// @param _max The max amount of seconds in the future for which an option expiration can be set
    function setMaxExpiration(uint256 _max) external onlyOwner {
        _maxExpiration = _max;
    }

    /// @notice Set a new max expiration date for deposits
    /// @param _max The max amount of seconds in the future for which a deposit expiration can be set
    function setMaxDepositExpiration(uint256 _max) external onlyOwner {
        maxDepositExpiration = _max;
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

    function getWritableAmount(AMMStruct.TokenPair memory _pair, uint256 _lockExpiration) public view returns (uint256) {
        uint256 expiration = _getNextExpiration();

        if (expiration < _lockExpiration) {
            expiration = _lockExpiration;
        }

        uint256 writableAmount;
        while (expiration <= block.timestamp + _maxExpiration) {
            PoolInfo memory pInfo = poolInfos[_pair.token][_pair.denominator][expiration];

            writableAmount += pInfo.amount - pInfo.amountLocked;
            expiration += _expirationIncrement;
        }

        return writableAmount;
    }

    /// @notice More gas efficient than getWritableAmount, as it stops iteration if amount required is reached
    function hasWritableAmount(AMMStruct.TokenPair memory _pair, uint256 _lockExpiration, uint256 _amount) public view returns(bool) {
        uint256 expiration = _getNextExpiration();

        if (expiration < _lockExpiration) {
            expiration = _lockExpiration;
        }

        uint256 writableAmount;
        while (expiration <= block.timestamp + _maxExpiration) {
            PoolInfo memory pInfo = poolInfos[_pair.token][_pair.denominator][expiration];

            writableAmount += pInfo.amount - pInfo.amountLocked;
            expiration += _expirationIncrement;

            if (writableAmount >= _amount) return true;
        }

        return false;
    }

    function getUnlockableAmount(address _user, address _token, address _denominator) external view returns(uint256) {
        require(_token != _denominator, "Token = Denominator");

        uint256 lastUnlock = userLastUnlock[_user][_token][_denominator];

        // If 0, no deposits has ever been made
        if (lastUnlock == 0) return 0;

        uint256 expiration = ((lastUnlock / _expirationIncrement) * _expirationIncrement) + _baseExpiration;

        uint256 unlockableAmount;
        while (expiration < block.timestamp) {
            UserInfo memory uInfo = userInfos[_user][_token][_denominator][expiration];

            unlockableAmount += uInfo.amount;
            expiration += _expirationIncrement;
        }

        return unlockableAmount;
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
            AMMStruct.TokenPair memory pair = AMMStruct.TokenPair(_token, _denominator);
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

    function getLoanableAmount(AMMStruct.TokenPair memory _pair, uint256 _lockExpiration) public view virtual returns (uint256) {
        uint256 writableAmount = getWritableAmount(_pair, _lockExpiration);
        return writableAmount * _inverseBasisPoint / maxLoanPercent;
    }

    function getRequiredCollateralToBorrowLoan(Loan memory _loan) public view returns (uint256) {
        uint256 expectedTime = _loan.lockExpiration - _loan.creationTime;

        // ToDo : Extract in an internal function as it is used at multiple places ?
        address collateralToken;
        uint256 tokenBorrowedPrice;
        uint256 collateralPrice;

        if (isTokenPool) {
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

        if (isTokenPool) {
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
                                     _amount,
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
        address collateralToken = isTokenPool ? _loan.denominator : _loan.token;

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

    function depositFrom(address _from, AMMStruct.TokenPair[] memory _pairs, uint256[] memory _amounts, uint256 _lockExpiration) external onlyController nonReentrant {
        require(_pairs.length == _amounts.length, "Arrays diff length");
        require(_lockExpiration > block.timestamp, "Exp passed");
        require(_lockExpiration - block.timestamp <= _maxExpiration, "Exp > max option exp");
        require(_lockExpiration - block.timestamp <= maxDepositExpiration, "Exp > max deposit exp");
        require(_lockExpiration % _expirationIncrement == _baseExpiration, "Wrong exp incr");

        for (uint256 i = 0; i < _pairs.length; i++) {
            address tokenDeposit = isTokenPool ? _pairs[i].token : _pairs[i].denominator;

            require(whitelistedPairs[_pairs[i].token][_pairs[i].denominator], "Pair not whitelisted");

            if (_amounts[i] == 0) continue;

            IERC20(tokenDeposit).safeTransferFrom(_from, address(this), _amounts[i]);

            address token = _pairs[i].token;
            address denominator = _pairs[i].denominator;

            UserInfo storage uInfo = userInfos[_from][token][denominator][_lockExpiration];
            PoolInfo storage pInfo = poolInfos[token][denominator][_lockExpiration];

            pInfo.amount += _amounts[i];

            uint256 multiplier = _inverseBasisPoint + ((_lockExpiration - block.timestamp) * maxScoreMultiplier / _maxExpiration);

            uInfo.amount += _amounts[i];
            uInfo.score += _amounts[i] * multiplier / _inverseBasisPoint;

            // If this is the first deposit ever made by this user, for this token
            if (userLastUnlock[_from][token][denominator] == 0) {
                userLastUnlock[_from][token][denominator] = block.timestamp;
            }

            emit Deposit(_from, tokenDeposit, denominator, isTokenPool, _lockExpiration, _amounts[i]);
        }
    }

    function withdrawExpiredFrom(address _from, AMMStruct.TokenPair[] memory _pairs) external onlyController nonReentrant {
        for (uint256 i = 0; i < _pairs.length; i++) {
            uint256 lastExpiration = _getNextExpiration() - _expirationIncrement;
            _unwindPool(_pairs[i].token, _pairs[i].denominator, lastExpiration);
            userLastUnlock[_from][_pairs[i].token][_pairs[i].denominator] = block.timestamp;

            // ToDo : Implement with PnL distribution based on score
//            if (tokenAmount > 0) {
//                IERC20(_pairs[i].token).safeTransfer(_from, tokenAmount);
//                emit Withdraw(_from, _pairs[i].token, _pairs[i].denominator, true, tokenAmount);
//            }
//
//            if (denominatorAmount > 0) {
//                IERC20(_pairs[i].denominator).safeTransfer(_from, denominatorAmount);
//                emit Withdraw(_from, _pairs[i].token, _pairs[i].denominator, false, denominatorAmount);
//            }
        }
    }

    function _lockTokens(AMMStruct.TokenPair memory _pair, uint256 _expiration, uint256 _amount, uint256 _amountPremium) internal {
        // Add to locked amounts (closest possible >= expiration of option)
        uint256 amountLeftToLock = _amount;

        while (_expiration <= block.timestamp + _maxExpiration) {
            PoolInfo storage pInfo = poolInfos[_pair.token][_pair.denominator][_expiration];

            uint256 amountUnlocked = pInfo.amount - pInfo.amountLocked;
            uint256 toLockForExp = amountLeftToLock > amountUnlocked ? amountUnlocked : amountLeftToLock;
            pInfo.amountLocked += toLockForExp;
            amountLeftToLock -= toLockForExp;

            // Distribute the profit from the premium, in a proportional amount to what is locked for this expiration
            uint256 ratioLocked = toLockForExp * 1e12 / _amount;
            pInfo.denominatorPnl += (_amountPremium * ratioLocked / 1e12).toInt256();

            if (amountLeftToLock == 0) {
                break;
            }

            _expiration += _expirationIncrement;
        }
    }

    function _unlockTokens(AMMStruct.TokenPair memory _pair, uint256 _expiration, uint256 _initialAmount, uint256 _finalTokenAmount, uint256 _finalDenominatorAmount) internal {
        uint256 amountLeftToUnlock = _initialAmount;

        while (_expiration <= block.timestamp + _maxExpiration) {
            PoolInfo storage pInfo = poolInfos[_pair.token][_pair.denominator][_expiration];

            uint256 toUnlockForExp = amountLeftToUnlock > pInfo.amountLocked ? pInfo.amountLocked : amountLeftToUnlock;
            pInfo.amountLocked -= toUnlockForExp;
            amountLeftToUnlock -= toUnlockForExp;

            // Distribute the token/denominator, in a proportional amount to what is unlocked for this expiration
            int256 ratioLocked = toUnlockForExp.toInt256() * 1e12 / _initialAmount.toInt256();

            if (isTokenPool) {
                pInfo.tokenPnl += (_finalTokenAmount.toInt256() - _initialAmount.toInt256()) * ratioLocked / 1e12;
                pInfo.denominatorPnl += _finalDenominatorAmount.toInt256() * ratioLocked / 1e12;
            } else {
                pInfo.tokenPnl += _finalTokenAmount.toInt256() * ratioLocked / 1e12;
                pInfo.denominatorPnl += (_finalDenominatorAmount.toInt256() - _initialAmount.toInt256()) * ratioLocked / 1e12;
            }

            if (amountLeftToUnlock == 0) {
                break;
            }

            _expiration += _expirationIncrement;
        }
    }

    function _lendCapital(Loan memory _loan) internal {
        AMMStruct.TokenPair memory pair = AMMStruct.TokenPair(_loan.token, _loan.denominator);
        uint256 loanableAmount = getLoanableAmount(pair, _loan.lockExpiration);
        uint256 collateralRequired = getRequiredCollateralToBorrowLoan(_loan);

        require(loanableAmount >= _loan.amountBorrow, "Amount too high.");
        require(collateralRequired <= _loan.amountCollateral, "Not enough collateral.");

        // ToDo : Review this + how to deal with PnL (premium amount for the particular exp from which funds are taken)
        _lockTokens(pair, _loan.lockExpiration, _loan.amountBorrow, 0);

        UserInfo storage uInfo = userInfos[msg.sender][_loan.token][_loan.denominator][_loan.lockExpiration];
        PoolInfo storage pInfo = poolInfos[_loan.token][_loan.denominator][_loan.lockExpiration];

        // ToDo : Review this, might need to account separately loans
        pInfo.amount += _loan.amountCollateral;
        uInfo.amount += _loan.amountCollateral;

        if (isTokenPool) {
            IERC20(_loan.denominator).safeTransferFrom(msg.sender, address(this), _loan.amountCollateral);
            IERC20(_loan.token).safeTransfer(msg.sender, _loan.amountBorrow);
        } else {
            IERC20(_loan.token).safeTransferFrom(msg.sender, address(this), _loan.amountCollateral);
            IERC20(_loan.denominator).safeTransfer(msg.sender, _loan.amountBorrow);
        }

        bytes32 hash = getLoanHash(_loan);
        loans[hash] = _loan;

        emit Borrow(hash, msg.sender, _loan.token, _loan.denominator, isTokenPool, _loan.lockExpiration, _loan.amountBorrow, _loan.amountCollateral, _loan.lendingRate);
    }

    function borrow(AMMStruct.TokenPair memory _pair, uint256 _amountBorrow, uint256 _amountCollateral, uint256 _lockExpiration) external nonReentrant returns (Loan memory) {
        bool borrowToken = isTokenPool;
        address collateralToken = isTokenPool ? _pair.denominator : _pair.token;

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

    function repay(bytes32 _hash, uint256 _amount) public nonReentrant returns (uint256) {
        Loan memory loan = loans[_hash];

        UserInfo storage uInfo = userInfos[loan.borrower][loan.token][loan.denominator][loan.lockExpiration];

        address borrowedToken = isTokenPool ? loan.token : loan.denominator;
        address collateralToken = isTokenPool ? loan.denominator : loan.token;
        uint256 collateralAmount = uInfo.amount;

        IERC20(borrowedToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 collateralOut;
        if (loan.amountBorrow - _amount == 0) {
            collateralOut = loan.amountCollateral;
            delete loans[_hash];
        } else {
            collateralOut = getRequiredCollateralToRepayLoan(loan, _amount);
            loans[_hash].amountBorrow -= _amount;
            loans[_hash].amountCollateral -= collateralOut;
        }

        require(collateralAmount >= collateralOut, "Not enough collateral.");

        PoolInfo storage pInfo = poolInfos[loan.token][loan.denominator][loan.lockExpiration];
        // ToDo : Review this, we might need to account loaned amounts separately
        pInfo.amount -= collateralOut;
        uInfo.amount -= collateralOut;

        IERC20(collateralToken).safeTransfer(loan.borrower, collateralOut);

        emit RepayLoan(_hash, msg.sender, loan.token, loan.denominator, isTokenPool, _amount);

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
            block.timestamp
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

        address collateralToken = isTokenPool ? loan.denominator : loan.token;

        require(loan.amountCollateral * _inverseBasisPoint / _collateralAmount >= maxPercentLiquidated, "Too much liquidated.");
        require(isLoanUnderCollateralized(loan) ||    loan.lockExpiration < block.timestamp, "Loan cannot be liquidated.");

        uint256 amountToken = _liquidateCollateral(collateralToken, loan.token, _collateralAmount);

        loan.amountBorrow -= amountToken;
        loan.amountCollateral -= _collateralAmount;

        UserInfo storage uInfo = userInfos[loan.borrower][loan.token][loan.denominator][loan.lockExpiration];
        PoolInfo storage pInfo = poolInfos[loan.token][loan.denominator][loan.lockExpiration];

        // ToDo: Review this, we might need to account loaned amounts separately
        uInfo.amount -= _collateralAmount;
        pInfo.amount -= _collateralAmount;

        // ToDo : Account for loss

        _postLiquidate(loan, _collateralAmount);

        uint256 rewardFee = (amountToken * _inverseBasisPoint) / liquidatorReward;

        IERC20(collateralToken).safeTransfer(msg.sender, rewardFee);

        if (loan.amountCollateral == 0) {
            delete loans[_hash];
        }

        // Fix this
        emit LiquidateLoan(_hash, msg.sender, loan.token, loan.denominator, isTokenPool, _collateralAmount, rewardFee);
    }

    function buyOption(address _from, address _optionContract, IPremiaOption.OptionWriteArgs memory _option, uint256 _amountPremium, address _referrer) public nonReentrant onlyController returns (uint256)  {
        if (_option.amount == 0) return 0;
        require(permissions[_optionContract].isWhitelistedOptionContract, "Option contract not whitelisted.");

        address denominator = IPremiaOption(_optionContract).denominator();
        IERC20(denominator).safeTransferFrom(_from, address(this), _amountPremium);

        uint256 amountToLock;

        // Token approval
        if (_option.isCall) {
            amountToLock = _option.amount;
            IERC20(_option.token).approve(_optionContract, _option.amount);
        } else {
            uint256 decimals = IERC20Extended(_option.token).decimals();
            amountToLock = (_option.amount * _option.strikePrice) / (10 ** decimals);
            IERC20(denominator).approve(_optionContract, amountToLock);
        }

        _lockTokens(AMMStruct.TokenPair(_option.token, denominator), _option.expiration, amountToLock, _amountPremium);

        uint256 optionId = IPremiaOption(_optionContract).writeOption(_option);
        _addOptionToList(_option.token, denominator, _option.expiration, OptionId(_optionContract, optionId));
        IPremiaOption(_optionContract).safeTransferFrom(address(this), _from, optionId, _option.amount, "");

        _afterBuyOption(_from, _optionContract, optionId, _option.amount, _amountPremium, _referrer);
        optionsOutstanding[_optionContract][optionId] += _option.amount;

        uint256 oldest = oldestOutstandingOption[_option.token][denominator];
        if (oldest == 0 || oldest > _option.expiration) {
            oldestOutstandingOption[_option.token][denominator] = _option.expiration;
        }

        emit BoughtOption(_from, _optionContract, optionId, _option.amount, denominator, _amountPremium);

        return optionId;
    }

    function _addOptionToList(address _token, address _denominator, uint256 _expiration, OptionId memory _optionId) internal {
        PoolInfo storage pInfo = poolInfos[_token][_denominator][_expiration];

        for (uint256 i=0; i < pInfo.optionIdList.length; i++) {
            OptionId memory oId = pInfo.optionIdList[i];

            if (oId.contractAddress == _optionId.contractAddress && oId.optionId == _optionId.optionId) return;
        }

        pInfo.optionIdList.push(_optionId);
    }

    function _afterBuyOption(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium, address _referrer) internal virtual {}

    // ToDo: _amount not used in any override, can we remove it ?
    // ToDo : Rename to make it more clear ?
    function _afterSellOption(address _optionContract, uint256 _optionId, uint256 _amount, uint256 _tokenWithdrawn, uint256 _denominatorWithdrawn) virtual internal {}

    function unwindPool(address _token, address _denominator, uint256 _expiration) public nonReentrant {
        _unwindPool(_token, _denominator, _expiration);
    }

    // ToDo : Do we add a reward for the user unwinding the pool ?
    function _unwindPool(address _token, address _denominator, uint256 _expiration) internal {
        require(block.timestamp >= _expiration, "Not expired");

        uint256 oldestExp = oldestOutstandingOption[_token][_denominator];
        if (oldestExp == 0 || oldestExp > _expiration) return;

        while (oldestExp <= _expiration) {
            PoolInfo storage pInfo = poolInfos[_token][_denominator][oldestExp];

            for (uint256 i=0; i < pInfo.optionIdList.length; i++) {
                OptionId memory optionId = pInfo.optionIdList[i];
                unwindOption(optionId.contractAddress, optionId.optionId);
            }

            oldestExp += _expirationIncrement;
            oldestOutstandingOption[_token][_denominator] = oldestExp;
        }
    }

    function unwindOption(address _optionContract, uint256 _optionId) public nonReentrant {
        uint256 outstanding = optionsOutstanding[_optionContract][_optionId];
        if (outstanding == 0) return;

        IPremiaOption optionContract = IPremiaOption(_optionContract);
        IPremiaOption.OptionData memory data = optionContract.optionData(_optionId);

        address denominator = optionContract.denominator();
        uint256 preTokenBalance = IERC20(data.token).balanceOf(address(this));
        uint256 preDenominatorBalance = IERC20(denominator).balanceOf(address(this));

        // Option contract has a check to make sure that the option is expired
        require(block.timestamp >= data.expiration, "Option not expired");
        optionContract.withdraw(_optionId);

        uint256 tokenWithdrawn = IERC20(data.token).balanceOf(address(this)) - preTokenBalance;
        uint256 denominatorWithdrawn = IERC20(denominator).balanceOf(address(this)) - preDenominatorBalance;

        uint256 amountTokenToUnlock;
        if (data.isCall) {
            amountTokenToUnlock = outstanding;
        } else {
            amountTokenToUnlock = (outstanding * data.strikePrice) / (10 ** data.decimals);
        }

        _unlockTokens(AMMStruct.TokenPair(data.token, denominator), data.expiration, amountTokenToUnlock, tokenWithdrawn, denominatorWithdrawn);

        _afterSellOption(_optionContract, _optionId, outstanding, tokenWithdrawn, denominatorWithdrawn);

        delete optionsOutstanding[_optionContract][_optionId];

        emit UnwindedOption(_optionContract, _optionId, outstanding);
    }

    function sellOption(address _from, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium) public nonReentrant onlyController {
        require(permissions[_optionContract].isWhitelistedOptionContract, "Option contract not whitelisted.");
        require(optionsOutstanding[_optionContract][_optionId] >= _amount, "Not enough written.");

        IPremiaOption optionContract = IPremiaOption(_optionContract);
        IPremiaOption.OptionData memory data = optionContract.optionData(_optionId);

        require(block.timestamp < data.expiration, "Option expired");
        IERC1155(optionContract).safeTransferFrom(_from, address(this), _optionId, _amount, "");

        address denominator = optionContract.denominator();

        optionsOutstanding[_optionContract][_optionId] -= _amount;

        IPremiaOption(_optionContract).cancelOption(_optionId, _amount);

        // Amount of tokens withdrawn from option contract and to be added as available in the pool
        uint256 tokenWithdrawn;
        uint256 denominatorWithdrawn;

        if (isTokenPool) {
            tokenWithdrawn = _amount;
            _unlockTokens(AMMStruct.TokenPair(data.token, denominator), data.expiration, _amount, _amount, 0);
        } else {
            denominatorWithdrawn = (_amount * data.strikePrice) / (10 ** data.decimals);
            _unlockTokens(AMMStruct.TokenPair(data.token, denominator), data.expiration, denominatorWithdrawn, 0, denominatorWithdrawn);
        }

        PoolInfo storage pInfo = poolInfos[data.token][denominator][data.expiration];
        // ToDo : If (denominatorAmount + denominatorPnl) ends up negative, loss needs to be repaid through swapping tokens
        pInfo.denominatorPnl -= _amountPremium.toInt256();
        IERC20(denominator).safeTransfer(_from, _amountPremium);

        _afterSellOption(_optionContract, _optionId, _amount, tokenWithdrawn, denominatorWithdrawn);

        emit SoldOption(_from, _optionContract, _optionId, _amount, denominator, _amountPremium);
    }
}