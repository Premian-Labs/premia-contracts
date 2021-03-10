// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../interface/IPremiaOption.sol';
import '../interface/IPriceOracleGetter.sol';
import '../uniswapV2/interfaces/IUniswapV2Router02.sol';
import "../interface/IPoolControllerChild.sol";

contract PremiaLiquidityPool is Ownable, ReentrancyGuard, IPoolControllerChild {
  using SafeERC20 for IERC20;

  struct Loan {
    address borrower;
    address token;
    uint256 amountOutstanding;
    address collateralToken;
    uint256 collateralHeld;
    uint256 tokenPrice;
    uint256 lockExpiration;
  }

  struct Permissions {
    bool canBorrow;
    bool canWrite;
    bool isWhitelistedRouter;
    bool isWhitelistedToken;
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

  // Fee rewarded to successful callers of the liquidate function
  uint256 public _liquidatorReward = 10;  // 10 = 0.1% fee
  // Max fee rewarded to successful callers of the liquidate function
  uint256 public constant _maxLiquidatorReward = 250;  // 250 = 25% fee
  uint256 public constant _inverseBasisPoint = 1000;

  address public controller;

  // The oracle used to get prices on chain.
  IPriceOracleGetter public priceOracle;
  
  // Mapping of addresses with special permissions (Contracts who can borrow / write or whitelisted routers / tokens)
  mapping(address => Permissions) public permissions;

  // Set a custom swap path for a token
  mapping(address => mapping(address => address[])) public customSwapPaths;

  // User -> Token -> Expiration -> Amount
  mapping(address => mapping(address => mapping (uint256 => uint256))) public depositsByUser;

  // User -> Token -> Timestamp
  mapping(address => mapping(address => uint256)) public userDepositsUnlockedUntil;

  // token => expiration => amount
  mapping(address => mapping(uint256 => uint256)) public amountsLockedByExpirationPerToken;
  
  // hash => loan
  mapping(bytes32 => Loan) public loansOutstanding;
  // optionContract => optionId => amountOutstanding
  mapping(address => mapping(uint256 => uint256)) public optionsOutstanding;

  ////////////
  // Events //
  ////////////

  event PermissionsUpdated(address indexed addr, bool canBorrow, bool canWrite, bool isWhitelistedRouter, bool isWhitelistedToken);
  event Deposit(address indexed user, address indexed token,uint256 lockExpiration, uint256 amountToken);
  event Withdraw(address indexed user, address indexed token, uint256 amountToken);
  event Borrow(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed lockExpiration, uint256 amount);
  event RepayLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount);
  event LiquidateLoan(bytes32 hash, address indexed borrower, address indexed token, uint256 indexed amount, uint256 rewardFee);
  event WriteOption(address indexed receiver, address indexed writer, address indexed optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium);
  event UnwindOption(address indexed sender, address indexed writer, address indexed optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium);
  event UnlockCollateral(address indexed unlocker, address indexed optionContract, uint256 indexed optionId, uint256 amount);
  event ControllerUpdated(address indexed newController);

  //////////////////////////////////////////////////
  //////////////////////////////////////////////////
  //////////////////////////////////////////////////

  constructor(address _controller) {
    controller = _controller;
  }

  //////////////////////////////////////////////////
  //////////////////////////////////////////////////
  //////////////////////////////////////////////////

  ///////////////
  // Modifiers //
  ///////////////

  modifier onlyController() {
    require(msg.sender == controller, "Caller is not the controller");
    _;
  }

  //////////////////////////////////////////////////
  //////////////////////////////////////////////////
  //////////////////////////////////////////////////

  ///////////
  // Admin //
  ///////////

  function upgradeController(address _newController) external override {
    require(msg.sender == owner() || msg.sender == controller, "Not owner or controller");
    controller = _newController;
    emit ControllerUpdated(_newController);
  }

  function setPermissions(address[] memory _addr, Permissions[] memory _permissions) external onlyOwner {
    require(_addr.length == _permissions.length, "Arrays diff length");

    for (uint256 i=0; i < _addr.length; i++) {
      permissions[_addr[i]] = _permissions[i];
      emit PermissionsUpdated(_addr[i], _permissions[i].canBorrow, _permissions[i].canWrite, _permissions[i].isWhitelistedRouter, _permissions[i].isWhitelistedToken);
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
    require(_reward <= _maxLiquidatorReward);
    _liquidatorReward = _reward;
  }

  /// @notice Set a new max percent liquidated
  /// @param _maxPercent New max percent
  function setMaxPercentLiquidated(uint256 _maxPercent) external onlyOwner {
    require(_maxPercent <= _inverseBasisPoint);
    _maxPercentLiquidated = _maxPercent;
  }

  /// @notice Set a custom swap path for a token
  /// @param _collateralToken The collateral token
  /// @param _token The token
  /// @param _path The swap path
  function setCustomSwapPath(address _collateralToken, address _token, address[] memory _path) external onlyOwner {
    customSwapPaths[_collateralToken][_token] = _path;
  }

  /// @notice Set the address of the oracle used for getting on-chain prices
  /// @param _priceOracleAddress The address of the oracle
  function setPriceOracle(address _priceOracleAddress) external onlyOwner {
    priceOracle = IPriceOracleGetter(_priceOracleAddress);
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

  function getLoanableAmount(address _token, uint256 _lockExpiration) public virtual returns (uint256) {
    // TODO: This likely needs to be adjusted based on the amounts currently loaned
    // and the amount of collateral stored in this contract

    return getWritableAmount(_token, _lockExpiration);
  }

  function getEquivalentCollateral(address _token, uint256 _amount, address _collateralToken) public returns (uint256) {
    uint256 tokenPrice = priceOracle.getAssetPrice(_token);
    uint256 collateralPrice = priceOracle.getAssetPrice(_collateralToken);
    return (_amount * tokenPrice) / collateralPrice;
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
      require(permissions[_tokens[i]].isWhitelistedToken, "Token not whitelisted");
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

      if (unlockedAmount == 0) return;

      IERC20(_tokens[i]).safeTransferFrom(address(this), _from, unlockedAmount);

      emit Withdraw(_from, _tokens[i], unlockedAmount);
    }
  }

  function borrow(address _token, uint256 _amountToken, address _collateralToken, uint256 _amountCollateral, uint256 _lockExpiration) external virtual nonReentrant {
    uint256 loanableAmount = getLoanableAmount(_token, _lockExpiration);
    uint256 collateralRequired = getEquivalentCollateral(_token, _amountToken, _collateralToken);

    // TODO: We need to set which tokens will be allowed as collateral

    require(loanableAmount >= _amountToken, "Amount too high.");
    require(permissions[msg.sender].canBorrow, "Borrow not whitelisted.");
    require(collateralRequired <= _amountCollateral, "Not enough collateral.");

    uint256 tokenPrice = priceOracle.getAssetPrice(_token);

    Loan memory loan = Loan(msg.sender, _token, _amountToken, _collateralToken, _amountCollateral, tokenPrice, _lockExpiration);

    IERC20(_token).safeTransferFrom(address(this), msg.sender, _amountToken);
    IERC20(_collateralToken).safeTransferFrom(msg.sender, address(this), _amountCollateral);

    bytes32 hash = getLoanHash(loan);

    loansOutstanding[hash] = loan;

    emit Borrow(hash, msg.sender, _token, _lockExpiration, _amountToken);
  }

  function repayLoan(Loan memory _loan, uint256 _amount) external virtual {
    bytes32 hash = getLoanHash(_loan);
    repay(hash, _amount);
  }

  function repay(bytes32 _hash, uint256 _amount) public virtual nonReentrant {
    Loan storage loan = loansOutstanding[_hash];

    uint256 collateralOut = getEquivalentCollateral(loan.token, _amount, loan.collateralToken);

    IERC20(loan.token).safeTransferFrom(msg.sender, address(this), _amount);

    loan.amountOutstanding = loan.amountOutstanding - _amount;

    if (loan.amountOutstanding == 0) {
      collateralOut = loan.collateralHeld;

      delete loansOutstanding[_hash];
    }

    IERC20(loan.collateralToken).safeTransferFrom(address(this), msg.sender, collateralOut);

    loan.collateralHeld = loan.collateralHeld - collateralOut;

    emit RepayLoan(_hash, msg.sender, loan.token, _amount);
  }

  function checkCollateralizationLevel(Loan memory _loan) public returns (bool) {
    uint256 collateralPrice = priceOracle.getAssetPrice(_loan.collateralToken);
    uint256 percentCollateralized = (_loan.collateralHeld * collateralPrice * _inverseBasisPoint) / (_loan.amountOutstanding * _loan.tokenPrice);
    return percentCollateralized >= _requiredCollateralizationPercent;
  }

  /// @notice Convert collateral back into original tokens
  /// @param _router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
  /// @param _collateralToken The token to swap from
  /// @param _token The token to swap collateral to
  /// @param _amountCollateral The amount of collateral
  function _liquidateCollateral(IUniswapV2Router02 _router, address _collateralToken, address _token, uint256 _amountCollateral) internal {
    require(permissions[address(_router)].isWhitelistedRouter, "Router not whitelisted.");

    IERC20(_collateralToken).safeIncreaseAllowance(address(_router), _amountCollateral);

    address weth = _router.WETH();
    address[] memory path = customSwapPaths[_collateralToken][_token];

    if (path.length == 0) {
      path = new address[](2);
      path[0] = _collateralToken;
      path[1] = weth;
    }

    path[path.length] = _token;

    _router.swapExactTokensForTokens(
      _amountCollateral,
      0,
      path,
      address(this),
      block.timestamp + 60
    );
  }

  function liquidateLoan(Loan memory _loan, uint256 _amount, IUniswapV2Router02 _router) external {
    bytes32 hash = getLoanHash(_loan);
    liquidate(hash, _amount, _router);
  }

  function liquidate(bytes32 _hash, uint256 _collateralAmount, IUniswapV2Router02 _router) public virtual nonReentrant {
    Loan storage loan = loansOutstanding[_hash];

    // TODO: Do we want to enable the following maximum liquidation percentage?
    // It limits the amount of collateral that can be liquidated at a single time.
    // The intent is to prevent liquidating collateral as much as possible.
    // However, it could have unintended consequences w/ our platform.

    // require(collateralHeld.mul(inverseBasisPoint).div(collateralAmount) >= _maxPercentLiquidated, "Too much liquidated.");

    // TODO: Allow loan to be liquidated if it's past the lockExpiration date

    require(!checkCollateralizationLevel(loan), "Loan is not under-collateralized.");
    require(permissions[address(_router)].isWhitelistedRouter, "Router not whitelisted.");

    _liquidateCollateral(_router, loan.collateralToken, loan.token, _collateralAmount);

    uint256 rewardFee = (_collateralAmount * _inverseBasisPoint) / _liquidatorReward;

    IERC20(loan.collateralToken).safeTransferFrom(address(this), msg.sender, rewardFee);

    if (loan.collateralHeld == 0) {
      delete loansOutstanding[_hash];
    }

    emit LiquidateLoan(_hash, msg.sender, loan.token, _collateralAmount, rewardFee);
  }

  function writeOption(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) external {
    writeOptionFor(msg.sender, _optionContract, _optionId, _amount, _premiumToken, _amountPremium, _referrer);
  }

  function writeOptionFor(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) public virtual nonReentrant {
    require(permissions[msg.sender].canWrite, "Writer not whitelisted.");

    // TODO: Should there be a limit to the amount we allow each contract to have outstanding?
    // We currently don't track who the contracts are outstanding to, so would need to update.
    // Would also need to set some standard rules for how much each contract can write.

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

    IPremiaOption(_optionContract).writeOption(data.token, writeArgs, _referrer);
    IPremiaOption(_optionContract).safeTransferFrom(address(this), _receiver, _optionId, _amount, "");

    emit WriteOption(_receiver, msg.sender, _optionContract, _optionId, _amount, _premiumToken, _amountPremium);
  }

  function unwindOption(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium) external {
    unwindOptionFor(msg.sender, _optionContract, _optionId, _amount, _premiumToken, _amountPremium);
  }

  function unwindOptionFor(address _sender, address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium) public virtual nonReentrant {
    require(permissions[msg.sender].canWrite, "Writer not whitelisted.");

    // TODO: I think we want to update this function to support exercising of ITM options.
    // I.e. "unwind" the option by exercising ITM for whatever it's worth
    // Or if it's not ITM, sell it to the pool for some premium, and the pool will cancel it

    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);

    if (data.expiration > block.timestamp) {
      IPremiaOption(_optionContract).withdraw(_optionId);

      // TODO: In this case, we might withdraw both the collateral token and the underlying token.
      // If we withdraw both, do we want to sell the collateral token at this time?
      // Or should we just keep both and save on trading fees + slippage?
    } else {
      IPremiaOption(_optionContract).cancelOptionFrom(_sender, _optionId, _amount);
    }

    uint256 outstanding = optionsOutstanding[_optionContract][_optionId];

    outstanding = outstanding - _amount;

    emit UnwindOption(_sender, msg.sender, _optionContract, _optionId, _amount, _premiumToken, _amountPremium);
  }

  function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) public virtual nonReentrant {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);

    require(data.expiration > block.timestamp, "Option is not expired yet.");

    IPremiaOption(_optionContract).withdraw(_optionId);

    // TODO: In this case, we might withdraw both the collateral token and the underlying token.
    // If we withdraw both, do we want to sell the collateral token at this time?
    // Or should we just keep both and save on trading fees + slippage?

    uint256 outstanding = optionsOutstanding[_optionContract][_optionId];

    outstanding = outstanding - _amount;

    // TODO: Reward unlocker for unlocking the collateral in the option

    emit UnlockCollateral(msg.sender, _optionContract, _optionId, _amount);
  }
}