// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../interface/IPremiaOption.sol';
import '../interface/IPriceOracleGetter.sol';
import '../interface/ILendingRateOracleGetter.sol';
import "../interface/IPremiaPoolController.sol";
import "../interface/IPoolControllerChild.sol";
import '../uniswapV2/interfaces/IUniswapV2Router02.sol';

contract PremiaLiquidityPool is Ownable, ReentrancyGuard, IPoolControllerChild {
  using SafeERC20 for IERC20;

  struct Loan {
    address lender;
    address borrower;
    address token;
    address collateralToken;
    uint256 amountTokenOutstanding;
    uint256 amountCollateralTokenHeld;
    uint256 creationTime;
    uint256 lockExpiration;
    uint256 tokenPrice;
    uint256 collateralPrice;
    uint256 lendingRate;
  }

  // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
  uint256 public constant _baseExpiration = 172799;
  // Expiration increment
  uint256 public constant _expirationIncrement = 1 weeks;
  // Max expiration time from now
  uint256 public _maxExpiration = 365 days;

  // Required collateralization level
  uint256 public _requiredCollateralizationPercent = 1000;  // 1000 = 100% collateralized
  // Max percent of collateral liquidated in a single liquidation event
  uint256 public _maxPercentLiquidated = 500;  // 500 = 50% of collateral
  // Max percent of capital allowed to be loaned in a single borrow event
  uint256 public _maxLoanPercent = 500;  // 250 = 25% of capital

  // Fee rewarded to successful callers of the liquidate function
  uint256 public _liquidatorReward = 10;  // 10 = 0.1% fee
  // Max fee rewarded to successful callers of the liquidate function
  uint256 public constant _maxLiquidatorReward = 250;  // 250 = 25% fee

  // Fee rewarded to successful callers of the unlockCollateral function
  uint256 public _unlockReward = 10;  // 10 = 0.1% fee
  // Max fee rewarded to successful callers of the unlockCollateral function
  uint256 public constant _maxUnlockReward = 250;  // 250 = 25% fee

  uint256 public constant _inverseBasisPoint = 1000;
  uint256 public constant WAD = 1e18;
  uint256 public constant WAD_RAY_RATIO = 1e9;
  uint256 public constant SECONDS_PER_YEAR = 365 days;

  IPremiaPoolController public controller;
  IPriceOracleGetter public priceOracle;
  ILendingRateOracleGetter public lendingRateOracle;

  // user address -> token address -> expiration -> amount
  mapping(address => mapping(address => mapping (uint256 => uint256))) public depositsByUser;

  // user address -> token address -> timestamp
  mapping(address => mapping(address => uint256)) public userDepositsUnlockedUntil;

  // token => expiration => amount
  mapping(address => mapping(uint256 => uint256)) public amountsLockedByExpirationPerToken;

  // token => expiration => amount
  mapping(address => mapping(uint256 => uint256)) public amountsWrittenByExpirationPerToken;

  // optionContract => optionId => amountTokenOutstanding
  mapping(address => mapping(uint256 => uint256)) public optionsOutstanding;
    
  // hash => Loan
  mapping(bytes32 => Loan) public loans;

  ////////////
  // Events //
  ////////////

  event Deposit(address indexed user, address indexed token,uint256 lockExpiration, uint256 amountToken);
  event Withdraw(address indexed user, address indexed token, uint256 amountToken);
  event Borrow(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed lockExpiration, uint256 amount, uint256 lendingRate);
  event RepayLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount);
  event LiquidateLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount, uint256 rewardFee);
  event WriteOption(address indexed receiver, address indexed writer, address indexed optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium);
  event UnwindOption(address indexed sender, address indexed writer, address indexed optionContract, uint256 optionId, uint256 amount);
  event UnlockCollateral(address indexed unlocker, address indexed optionContract, uint256 indexed optionId, uint256 amount, uint256 tokenRewardFee, uint256 denominatorRewardFee);
  event ControllerUpdated(address indexed newController);

  //////////////////////////////////////////////////
  //////////////////////////////////////////////////
  //////////////////////////////////////////////////

  constructor(IPremiaPoolController _controller, IPriceOracleGetter _priceOracle, ILendingRateOracleGetter _lendingRateOracle) {
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
    controller = IPremiaPoolController(_newController);
    emit ControllerUpdated(_newController);
  }

  /// @notice Set a new max expiration date for options writing (By default, 1 year from current date)
  /// @param _max The max amount of seconds in the future for which an option expiration can be set
  function setMaxExpiration(uint256 _max) external onlyOwner {
    _maxExpiration = _max;
  }

  /// @notice Set a new liquidator reward
  /// @param _reward New reward
  function setLiquidatorReward(uint256 _reward) external onlyOwner {
    require(_reward <= _maxLiquidatorReward);
    _liquidatorReward = _reward;
  }

  /// @notice Set a new unlock reward
  /// @param _reward New reward
  function setUnlockReward(uint256 _reward) external onlyOwner {
    require(_reward <= _maxUnlockReward);
    _unlockReward = _reward;
  }

  /// @notice Set a new max percent liquidated
  /// @param _maxPercent New max percent
  function setMaxPercentLiquidated(uint256 _maxPercent) external onlyOwner {
    require(_maxPercent <= _inverseBasisPoint);
    _maxPercentLiquidated = _maxPercent;
  }

  /// @notice Set a new max loan percent
  /// @param _maxPercent New max percent
  function setMaxLoanPercent(uint256 _maxPercent) external onlyOwner {
    require(_maxPercent <= _inverseBasisPoint);
    _maxLoanPercent = _maxPercent;
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
  
  function getUnwritableAmount(address _token, uint256 _lockExpiration) public view returns (uint256) {
    return amountsWrittenByExpirationPerToken[_token][_lockExpiration];
  }

  function getWritableAmount(address _token, uint256 _lockExpiration) public view returns (uint256) {
    uint256 expiration = _getNextExpiration();

    if (expiration < _lockExpiration) {
      expiration = _lockExpiration;
    }

    uint256 writableAmount;
    while (expiration <= block.timestamp + _maxExpiration) {
      writableAmount += amountsLockedByExpirationPerToken[_token][expiration];
      expiration += _expirationIncrement;
    }

    return writableAmount;
  }

  /// @notice More gas efficient than getWritableAmount, as it stops iteration if amount required is reached
  function hasWritableAmount(address _token, uint256 _lockExpiration, uint256 _amount) public view returns(bool) {
    uint256 expiration = _getNextExpiration();

    if (expiration < _lockExpiration) {
      expiration = _lockExpiration;
    }

    uint256 writableAmount;
    while (expiration <= block.timestamp + _maxExpiration) {
      writableAmount += amountsLockedByExpirationPerToken[_token][expiration];
      expiration += _expirationIncrement;

      if (writableAmount >= _amount) return true;
    }

    return false;
  }

  function getUnlockableAmount(address _user, address _token) external view returns (uint256) {
    uint256 unlockedUntil = userDepositsUnlockedUntil[msg.sender][_token];

    // If 0, no deposits has ever been made
    if (unlockedUntil == 0) return 0;

    uint256 expiration = ((unlockedUntil / _expirationIncrement) * _expirationIncrement) + _baseExpiration;

    uint256 unlockableAmount;
    while (expiration < block.timestamp) {
      unlockableAmount += depositsByUser[msg.sender][_token][expiration];
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

  function _getLoanPool(address _token, address _denominator, uint256 _expiration, bool _isCall, uint256 _amount) internal returns (PremiaLiquidityPool) {
    PremiaLiquidityPool[] memory liquidityPools = _isCall ?  controller.getCallPools() : controller.getPutPools();

    for (uint256 i = 0; i < liquidityPools.length; i++) {
      PremiaLiquidityPool pool = liquidityPools[i];
      uint256 amountAvailable = pool.getLoanableAmount(_isCall ? _token : _denominator, _expiration);

      if (amountAvailable >= _amount) {
        return pool;
      }
    }

    revert("Not enough liquidity");
  }

  function _getAmountToBorrow(uint256 _amount, address collateralToken, address tokenToBorrow) internal view returns (uint256) {
    uint256 priceOfCollateral = priceOracle.getAssetPrice(collateralToken);
    uint256 priceOfBorrowed = priceOracle.getAssetPrice(tokenToBorrow);
    return (_amount * _inverseBasisPoint / 997) * priceOfCollateral / priceOfBorrowed;
  }

  function getLoanableAmount(address _token, uint256 _lockExpiration) public virtual returns (uint256) {
    uint256 writableAmount = getWritableAmount(_token, _lockExpiration);
    return writableAmount * _inverseBasisPoint / _maxLoanPercent;
  }

  function getEquivalentCollateral(uint256 _tokenPrice, uint256 _collateralPrice, uint256 _amount) public view returns (uint256) {
    return (_amount * _tokenPrice) / _collateralPrice;
  }

  function getRequiredCollateralToBorrowLoan(Loan memory _loan, uint256 _amount) public view returns (uint256) {
    uint256 expectedTime = _loan.lockExpiration - _loan.creationTime;
    return getRequiredCollateral(_loan.collateralToken,
                                 _loan.tokenPrice,
                                 _loan.collateralPrice,
                                 _loan.amountTokenOutstanding,
                                 _loan.lendingRate,
                                 expectedTime);
  }

  function getRequiredCollateralToRepayLoan(Loan memory _loan, uint256 _amount) public view returns (uint256) {
    uint256 timeElapsed = block.timestamp - _loan.creationTime;
    return getRequiredCollateral(_loan.collateralToken,
                                 _loan.tokenPrice,
                                 _loan.collateralPrice,
                                 _loan.amountTokenOutstanding,
                                 _loan.lendingRate,
                                 timeElapsed);
  }

  function getRequiredCollateral(address _collateralToken,
                                 uint256 _tokenPrice,
                                 uint256 _collateralPrice,
                                 uint256 _amount,
                                 uint256 _lendingRate,
                                 uint256 _loanLengthInSeconds) public view returns (uint256) {
    uint256 equivalentCollateral = getEquivalentCollateral(_tokenPrice, _collateralPrice, _amount);
    uint256 ltvRatio = controller.getLoanToValueRatio(_collateralToken);
    uint256 expectedCompoundInterest = calculateCompoundInterest(_lendingRate, _loanLengthInSeconds);
    return (equivalentCollateral * _inverseBasisPoint / ltvRatio) + expectedCompoundInterest;
  }

  function _unlockExpired(address _token) internal returns(uint256) {
    uint256 unlockedUntil = userDepositsUnlockedUntil[msg.sender][_token];

    // If 0, no deposits has ever been made
    if (unlockedUntil == 0) return 0;

    uint256 expiration = ((unlockedUntil / _expirationIncrement) * _expirationIncrement) + _baseExpiration;

    uint256 unlockedToken;
    while (expiration < block.timestamp) {
      uint256 amount = depositsByUser[msg.sender][_token][expiration];

      delete depositsByUser[msg.sender][_token][expiration];

      amountsLockedByExpirationPerToken[_token][expiration] -= amount;
      unlockedToken += amount;
      expiration += _expirationIncrement;
    }

    userDepositsUnlockedUntil[msg.sender][_token] = block.timestamp;

    return unlockedToken;
  }

  function depositFrom(address _from, address[] memory _tokens, uint256[] memory _amounts, uint256 _lockExpiration) external onlyController {
    _deposit(_from, _tokens, _amounts, _lockExpiration);
  }

  function _deposit(address _from, address[] memory _tokens, uint256[] memory _amounts, uint256 _lockExpiration) internal nonReentrant {
    require(_tokens.length == _amounts.length, "Arrays diff length");
    require(_lockExpiration > block.timestamp, "Exp passed");
    require(_lockExpiration - block.timestamp <= _maxExpiration, "Exp > max exp");
    require(_lockExpiration % _expirationIncrement == _baseExpiration, "Wrong exp incr");

    for (uint256 i = 0; i < _tokens.length; i++) {
      require(controller.getPermissions(_tokens[i]).isWhitelistedToken, "Token not whitelisted");

      if (_amounts[i] == 0) continue;

      IERC20(_tokens[i]).safeTransferFrom(_from, address(this), _amounts[i]);
      amountsLockedByExpirationPerToken[_tokens[i]][_lockExpiration] += _amounts[i];
      depositsByUser[_from][_tokens[i]][_lockExpiration] += _amounts[i];

      // If this is the first deposit ever made by this user, for this token
      if (userDepositsUnlockedUntil[_from][_tokens[i]] == 0) {
        userDepositsUnlockedUntil[_from][_tokens[i]] = block.timestamp;
      }

      emit Deposit(_from, _tokens[i], _lockExpiration, _amounts[i]);
    }
  }

  function withdrawExpiredFrom(address _from, address[] memory _tokens) external onlyController {
    _withdrawExpired(_from, _tokens);
  }

  function _withdrawExpired(address _from, address[] memory _tokens) internal nonReentrant {
    for (uint256 i = 0; i < _tokens.length; i++) {
      uint256 unlockedAmount = _unlockExpired(_tokens[i]);

      if (unlockedAmount == 0) continue;

      IERC20(_tokens[i]).safeTransferFrom(address(this), _from, unlockedAmount);

      emit Withdraw(_from, _tokens[i], unlockedAmount);
    }
  }

  function _subtractLockedAmounts(address _token, uint256 _lockExpiration, uint256 _amount) internal {
    uint256 expiration = _lockExpiration;
    uint256 amountLeft = _amount;

    uint256 amountLocked;
    while (amountLeft > 0 && expiration <= block.timestamp + _maxExpiration) {
      amountLocked = amountsLockedByExpirationPerToken[_token][expiration];

      if (amountLocked > amountLeft) {
        amountsLockedByExpirationPerToken[_token][expiration] -= amountLeft;
        amountLeft = 0;
        return;
      } else {
        amountsLockedByExpirationPerToken[_token][expiration] = 0;
        amountLeft -= amountLocked;
      }

      expiration += _expirationIncrement;
    }

    if (amountLeft > 0)
      revert();
  }

  function _lendCapital(Loan memory _loan) internal {                   
    uint256 loanableAmount = getLoanableAmount(_loan.token, _loan.lockExpiration);
    uint256 collateralRequired = getRequiredCollateralToBorrowLoan(_loan, _loan.amountTokenOutstanding);

    require(loanableAmount >= _loan.amountTokenOutstanding, "Amount too high.");
    require(collateralRequired <= _loan.amountCollateralTokenHeld, "Not enough collateral.");

    _subtractLockedAmounts(_loan.token, _loan.lockExpiration, _loan.amountTokenOutstanding);

    amountsLockedByExpirationPerToken[_loan.collateralToken][_loan.lockExpiration] += _loan.amountCollateralTokenHeld;
    depositsByUser[msg.sender][_loan.collateralToken][_loan.lockExpiration] += _loan.amountCollateralTokenHeld;

    IERC20(_loan.token).safeTransferFrom(address(this), msg.sender, _loan.amountTokenOutstanding);
    IERC20(_loan.collateralToken).safeTransferFrom(msg.sender, address(this), _loan.amountCollateralTokenHeld);

    bytes32 hash = getLoanHash(_loan);
    loans[hash] = _loan;

    emit Borrow(hash, msg.sender, _loan.token, _loan.lockExpiration, _loan.amountTokenOutstanding, _loan.lendingRate);
  }

  function borrow(address _token, uint256 _amountToken, address _collateralToken, uint256 _amountCollateral, uint256 _lockExpiration)
    external virtual nonReentrant returns (Loan memory) {
    require(controller.getLoanToValueRatio(_collateralToken) > 0, "Collateral token not allowed.");
    require(controller.getPermissions(msg.sender).canBorrow, "Borrow not whitelisted.");

    uint256 tokenPrice = priceOracle.getAssetPrice(_token);
    uint256 collateralPrice = priceOracle.getAssetPrice(_collateralToken);
    uint256 lendingRate = rayToWad(lendingRateOracle.getMarketBorrowRate(_token));

    Loan memory loan = Loan(address(this),
                            msg.sender,
                            _token,
                            _collateralToken,
                            _amountToken,
                            _amountCollateral,
                            block.timestamp,
                            _lockExpiration,
                            tokenPrice,
                            collateralPrice,
                            lendingRate);

    _lendCapital(loan);

    return loan;
  }

  function repayLoan(Loan memory _loan, uint256 _amount) external virtual returns (uint256) {
    bytes32 hash = getLoanHash(_loan);
    return repay(hash, _amount);
  }

  function repay(bytes32 _hash, uint256 _amount) public virtual nonReentrant returns (uint256) {
    Loan storage loan = loans[_hash];

    uint256 collateralOut = getRequiredCollateralToRepayLoan(loan, _amount);

    require(depositsByUser[loan.borrower][loan.collateralToken][loan.lockExpiration] >= collateralOut, "Not enough collateral.");

    IERC20(loan.token).safeTransferFrom(msg.sender, address(this), _amount);

    loan.amountTokenOutstanding = loan.amountTokenOutstanding - _amount;

    if (loan.amountTokenOutstanding == 0) {
      collateralOut = loan.amountCollateralTokenHeld;

      delete loans[_hash];
    }

    loan.amountCollateralTokenHeld = loan.amountCollateralTokenHeld - collateralOut;
    amountsLockedByExpirationPerToken[loan.collateralToken][loan.lockExpiration] -= collateralOut;
    depositsByUser[loan.borrower][loan.collateralToken][loan.lockExpiration] -= collateralOut;

    IERC20(loan.collateralToken).safeTransferFrom(address(this), loan.borrower, collateralOut);

    emit RepayLoan(_hash, msg.sender, loan.token, _amount);

    return collateralOut;
  }

  function isLoanUnderCollateralized(Loan memory _loan) public view returns (bool) {
    uint256 collateralPrice = priceOracle.getAssetPrice(_loan.collateralToken);
    uint256 percentCollateralized = (_loan.amountCollateralTokenHeld * collateralPrice * _inverseBasisPoint) / (_loan.amountTokenOutstanding * _loan.tokenPrice);
    return percentCollateralized < _requiredCollateralizationPercent;
  }

  /// @notice Convert collateral back into original tokens
  /// @param _inputToken The token to swap from
  /// @param _outputToken The token to swap to
  /// @param _amountIn The amount of _inputToken to swap
  function _swapTokensIn(address _inputToken, address _outputToken, uint256 _amountIn) internal returns (uint256) {
    IUniswapV2Router02 router = controller.getDesignedSwapRouter(_inputToken, _outputToken);

    IERC20(_inputToken).safeIncreaseAllowance(address(router), _amountIn);

    address weth = router.WETH();
    address[] memory path = controller.getCustomSwapPath(_inputToken, _outputToken);

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

  function liquidate(bytes32 _hash, uint256 _collateralAmount) public virtual nonReentrant {
    Loan storage loan = loans[_hash];

    require(loan.amountCollateralTokenHeld * _inverseBasisPoint / _collateralAmount >= _maxPercentLiquidated, "Too much liquidated.");
    require(isLoanUnderCollateralized(loan) ||  loan.lockExpiration < block.timestamp, "Loan cannot be liquidated.");

    uint256 amountToken = _liquidateCollateral(loan.collateralToken, loan.token, _collateralAmount);

    loan.amountTokenOutstanding -= amountToken;
    loan.amountCollateralTokenHeld -= _collateralAmount;

    amountsLockedByExpirationPerToken[loan.collateralToken][loan.lockExpiration] -= _collateralAmount;
    depositsByUser[loan.borrower][loan.collateralToken][loan.lockExpiration] -= _collateralAmount;

    _postLiquidate(loan, _collateralAmount);

    uint256 rewardFee = (amountToken * _inverseBasisPoint) / _liquidatorReward;

    IERC20(loan.token).safeTransferFrom(address(this), msg.sender, rewardFee);

    if (loan.amountCollateralTokenHeld == 0) {
      delete loans[_hash];
    }

    emit LiquidateLoan(_hash, msg.sender, loan.token, _collateralAmount, rewardFee);
  }

  function writeOption(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) external {
    writeOptionFor(msg.sender, _optionContract, _optionId, _amount, _premiumToken, _amountPremium, _referrer);
  }

  function writeOptionFor(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) public virtual nonReentrant {
    require(controller.getPermissions(msg.sender).canWrite, "Writer not whitelisted.");

    uint256 outstanding = optionsOutstanding[_optionContract][_optionId];

    outstanding = outstanding + _amount;

    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    IPremiaOption.OptionWriteArgs memory writeArgs = IPremiaOption.OptionWriteArgs({
        amount: _amount,
        token: data.token,
        strikePrice: data.strikePrice,
        expiration: data.expiration,
        isCall: data.isCall
    });

    _subtractLockedAmounts(data.token, data.expiration, _amount);

    amountsWrittenByExpirationPerToken[data.token][data.expiration] += _amount;

    IPremiaOption(_optionContract).writeOption(data.token, writeArgs, _referrer);
    IPremiaOption(_optionContract).safeTransferFrom(address(this), _receiver, _optionId, _amount, "");

    emit WriteOption(_receiver, msg.sender, _optionContract, _optionId, _amount, _premiumToken, _amountPremium);
  }

  // ToDo: _amount not used in any override, can we remove it ?
  function _postWithdrawal(address _optionContract, uint256 _optionId, uint256 _amount, uint256 _tokenWithdrawn, uint256 _denominatorWithdrawn) virtual internal {}

  function unwindOption(address _optionContract, uint256 _optionId, uint256 _amount) external {
    unwindOptionFor(msg.sender, _optionContract, _optionId, _amount);
  }

  function unwindOptionFor(address _sender, address _optionContract, uint256 _optionId, uint256 _amount) public virtual nonReentrant {
    require(controller.getPermissions(msg.sender).canWrite, "Writer not whitelisted.");

    IPremiaOption optionContract = IPremiaOption(_optionContract);
    IPremiaOption.OptionData memory data = optionContract.optionData(_optionId);

    address denominatorToken = optionContract.denominator();
    uint256 preTokenBalance = IERC20(data.token).balanceOf(address(this));
    uint256 preDenominatorBalance = IERC20(denominatorToken).balanceOf(address(this));
    uint256 outstanding = optionsOutstanding[_optionContract][_optionId];

    optionsOutstanding[_optionContract][_optionId] = outstanding - _amount;
    amountsWrittenByExpirationPerToken[data.token][data.expiration] -= _amount;

    if (data.expiration > block.timestamp) {
      IPremiaOption(_optionContract).withdraw(_optionId);
    } else {
      IPremiaOption(_optionContract).cancelOptionFrom(_sender, _optionId, _amount);
    }

    uint256 tokenWithdrawn = IERC20(data.token).balanceOf(address(this)) - preTokenBalance;
    uint256 denominatorWithdrawn = IERC20(denominatorToken).balanceOf(address(this)) - preDenominatorBalance;

    _postWithdrawal(_optionContract, _optionId, _amount, tokenWithdrawn, denominatorWithdrawn);
    
    // TODO: the following should probably not use `max expiration` or `date.expiration`, but rather the original date the amount
    // was locked until. However, this is not currently saved anywhere.
    //
    // The following situation shows the importance of fixing this issue:
    // IF `data.expiration` is used:
    // User A deposits Token A locked for 1 Year.
    // User B immediately purchases call options of Token A, with expiration 1 week out, for the full amount deposited by User A.
    // 1 week later, User A's tokens are unlocked, but the user still cannot withdraw their tokens for 51 weeks
    // User A's tokens can no longer be used to write options on the market, and cannot be withdrawn for 51 weeks.
    // OR
    // IF `maxExpiration` is used:
    // User A deposits Token A locked for 2 weeks.
    // User B immediately purchases call options of Token A, with expiration 1 week out, for the full amount deposited by User A.
    // 1 week later, User A's tokens are locked for 52 weeks, but the user can withdraw their tokens for 1 week.
    // Meaning if the user tries to withdraw after the total 2 weeks, there may not be enough liquidity available for the next 51 weeks.

    uint256 maxExpiration = _getNextExpiration() + _maxExpiration;

    amountsLockedByExpirationPerToken[data.token][maxExpiration] += tokenWithdrawn;
    amountsLockedByExpirationPerToken[denominatorToken][maxExpiration] += denominatorWithdrawn;

    emit UnwindOption(_sender, msg.sender, _optionContract, _optionId, _amount);
  }

  function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) public virtual nonReentrant {
    IPremiaOption optionContract = IPremiaOption(_optionContract);
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);

    require(data.expiration > block.timestamp, "Option is not expired yet.");

    address denominatorToken = optionContract.denominator();
    uint256 preTokenBalance = IERC20(data.token).balanceOf(address(this));
    uint256 preDenominatorBalance = IERC20(denominatorToken).balanceOf(address(this));
    uint256 outstanding = optionsOutstanding[_optionContract][_optionId];

    optionsOutstanding[_optionContract][_optionId] = outstanding - _amount;
    amountsWrittenByExpirationPerToken[data.token][data.expiration] -= _amount;

    IPremiaOption(_optionContract).withdraw(_optionId);

    uint256 tokenWithdrawn = IERC20(data.token).balanceOf(address(this)) - preTokenBalance;
    uint256 denominatorWithdrawn = IERC20(denominatorToken).balanceOf(address(this)) - preDenominatorBalance;

    _postWithdrawal(_optionContract, _optionId, _amount, tokenWithdrawn, denominatorWithdrawn);

    uint256 tokenRewardFee = (tokenWithdrawn * _inverseBasisPoint) / _unlockReward;
    uint256 denominatorRewardFee = (denominatorWithdrawn * _inverseBasisPoint) / _unlockReward;
    
    // TODO: the following should probably not use `max expiration` or `date.expiration`, but rather the original date the amount
    // was locked until. However, this is not currently saved anywhere.
    //
    // The following situation shows the importance of fixing this issue:
    // IF `data.expiration` is used:
    // User A deposits Token A locked for 1 Year.
    // User B immediately purchases call options of Token A, with expiration 1 week out, for the full amount deposited by User A.
    // 1 week later, User A's tokens are unlocked, but the user still cannot withdraw their tokens for 51 weeks
    // User A's tokens can no longer be used to write options on the market, and cannot be withdrawn for 51 weeks.
    // OR
    // IF `maxExpiration` is used:
    // User A deposits Token A locked for 2 weeks.
    // User B immediately purchases call options of Token A, with expiration 1 week out, for the full amount deposited by User A.
    // 1 week later, User A's tokens are locked for 52 weeks, but the user can withdraw their tokens for 1 week.
    // Meaning if the user tries to withdraw after the total 2 weeks, there may not be enough liquidity available for the next 51 weeks.

    uint256 maxExpiration = _getNextExpiration() + _maxExpiration;

    amountsLockedByExpirationPerToken[data.token][maxExpiration] += (tokenWithdrawn - tokenRewardFee);
    amountsLockedByExpirationPerToken[denominatorToken][maxExpiration] += (denominatorWithdrawn - denominatorRewardFee);
    
    if (tokenWithdrawn > 0 && denominatorWithdrawn > 0) {
      IERC20(data.token).safeTransferFrom(address(this), msg.sender, tokenRewardFee);
      IERC20(denominatorToken).safeTransferFrom(address(this), msg.sender, denominatorRewardFee);
    } else if (tokenWithdrawn > 0) {
      IERC20(data.token).safeTransferFrom(address(this), msg.sender, tokenRewardFee);
    } else {
      IERC20(denominatorToken).safeTransferFrom(address(this), msg.sender, denominatorRewardFee);
    }

    emit UnlockCollateral(msg.sender, _optionContract, _optionId, _amount, tokenRewardFee, denominatorRewardFee);
  }

  function rayToWad(uint256 a) internal pure returns (uint256) {
      uint256 halfRatio = WAD_RAY_RATIO / 2;
      return (halfRatio + a) / WAD_RAY_RATIO;
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
}