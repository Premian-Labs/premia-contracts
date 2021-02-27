// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';

import '../interface/IPremiaOption.sol';
import '../interface/IPriceOracleGetter.sol';
import '../uniswapV2/interfaces/IUniswapV2Router02.sol';

contract PremiaNeutralPool is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

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
  uint256 public _maxExpiration = 365 days;

  // Required collateralization level
  uint256 public _requiredCollaterizationPercent = 100;  // 100 = 100% collateralized
  // Max percent of collateral liquidated in a single liquidation event
  uint256 public _maxPercentLiquidated = 500;  // 500 = 50% of collateral

  // Fee rewarded to successful callers of the liquidate function
  uint256 public _liquidatorReward = 10;  // 10 = 0.1% fee
  // Max fee rewarded to successful callers of the liquidate function
  uint256 public constant _maxLiquidatorReward = 250;  // 250 = 25% fee

  uint256 private constant _inverseBasisPoint = 1000;

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


  /// @notice Add contract addresses to the list of whitelisted borrower contracts
  /// @param _addr The list of addresses to add
  function addWhitelistedBorrowContracts(address[] memory _addr) external onlyOwner {
      for (uint256 i=0; i < _addr.length; i++) {
          _whitelistedBorrowContracts.add(_addr[i]);
      }
  }

  /// @notice Remove contract addresses from the list of whitelisted borrower contracts
  /// @param _addr The list of addresses to remove
  function removeWhitelistedBorrowContracts(address[] memory _addr) external onlyOwner {
      for (uint256 i=0; i < _addr.length; i++) {
          _whitelistedBorrowContracts.remove(_addr[i]);
      }
  }

  /// @notice Get the list of whitelisted borrower contracts
  /// @return The list of whitelisted borrower contracts
  function getWhitelistedBorrowContracts() external view returns(address[] memory) {
      uint256 length = _whitelistedBorrowContracts.length();
      address[] memory result = new address[](length);

      for (uint256 i=0; i < length; i++) {
          result[i] = _whitelistedBorrowContracts.at(i);
      }

      return result;
  }

  /// @notice Add contract addresses to the list of whitelisted writer contracts
  /// @param _addr The list of addresses to add
  function addWhitelistedWriterContracts(address[] memory _addr) external onlyOwner {
      for (uint256 i=0; i < _addr.length; i++) {
          _whitelistedWriterContracts.add(_addr[i]);
      }
  }

  /// @notice Remove contract addresses from the list of whitelisted writer contracts
  /// @param _addr The list of addresses to remove
  function removeWhitelistedWriterContracts(address[] memory _addr) external onlyOwner {
      for (uint256 i=0; i < _addr.length; i++) {
          _whitelistedWriterContracts.remove(_addr[i]);
      }
  }

  /// @notice Get the list of whitelisted writer contracts
  /// @return The list of whitelisted writer contracts
  function getWhitelistedWriterContracts() external view returns(address[] memory) {
      uint256 length = _whitelistedWriterContracts.length();
      address[] memory result = new address[](length);

      for (uint256 i=0; i < length; i++) {
          result[i] = _whitelistedWriterContracts.at(i);
      }

      return result;
  }

  /// @notice Add UniswapRouters to the whitelist so that they can be used to swap tokens.
  /// @param _addr The addresses to add to the whitelist
  function addWhitelistedRouterContracts(address[] memory _addr) external onlyOwner {
      for (uint256 i=0; i < _addr.length; i++) {
          _whitelistedRouterContracts.add(_addr[i]);
      }
  }

  /// @notice Remove UniswapRouters from the whitelist so that they cannot be used to swap tokens.
  /// @param _addr The addresses to remove the whitelist
  function removeWhitelistedRouterContracts(address[] memory _addr) external onlyOwner {
      for (uint256 i=0; i < _addr.length; i++) {
          _whitelistedRouterContracts.remove(_addr[i]);
      }
  }

  //////////////////////////

  /// @notice Get the list of whitelisted router contracts
  /// @return The list of whitelisted router contracts
  function getWhitelistedRouterContracts() external view returns(address[] memory) {
      uint256 length = _whitelistedRouterContracts.length();
      address[] memory result = new address[](length);

      for (uint256 i=0; i < length; i++) {
          result[i] = _whitelistedRouterContracts.at(i);
      }

      return result;
  }

  /// @notice Set a new liquidator reward
  /// @param _reward New reward
  function setLiquidatorReward(uint256 _reward) external onlyOwner {
      require(_reward <= _maxLiquidatorReward);
      _liquidatorReward = _reward;
  }

  /// @notice Set a new max percent liquidated
  /// @param _reward New max percent
  function setMaxPercentLiquidated(uint256 _maxPercent) external onlyOwner {
      require(_reward <= _inverseBasisPoint);
      _maxPercentLiquidated = _maxPercent;
  }

  /// @notice Set a custom swap path for a token
  /// @param _token The token
  /// @param _path The swap path
  function setCustomSwapPath(address collateralToken, address token, address[] memory path) external onlyOwner {
      customSwapPaths[collateralToken][token] = path;
  }

  /// @notice Set the address of the oracle used for getting on-chain prices
  /// @param priceOracleAddress The address of the oracle
  function setPriceOracle(address priceOracleAddress) external onlyOwner {
    priceOracle = IPriceOracleGetter(priceOracleAddress);
  }
  
  /// @notice Get the hash of an loan
  /// @param _loan The loan from which to calculate the hash
  /// @return The loan hash
  function getLoanHash(Loan memory loan) public pure returns(bytes32) {
      return keccak256(abi.encode(loan));
  }

  function getUnlockableAmounts(address token, address denominator, uint256 amountToken, uint256 amountDenominator) external returns (uint256 unlockableToken, uint256 unlockableDenominator) {
    UserDeposit[] memory depositsForUser = depositsByUser[msg.sender];
    uint256 unlockableToken;
    uint256 unlockableDenominator;

    for (uint256 i = 0; i < depositsForUser.length; i++) {
      UserDeposit memory deposit = depositsForUser[i];

      if (deposit.lockExpiration <= block.timestamp) {
        unlockableToken = unlockableToken.add(deposit.amountToken);
        unlockableDenominator = unlockableDenominator.add(deposit.amountDenominator);
      }
    }
  }

  function getCurrentWeekTimestamp() public returns (uint256 currentWeek) {
    uint256 currentWeek = _baseExpiration;

    while (currentWeek < block.timestamp) {
      currentWeek = currentWeek.add(_expirationIncrement);
    }
  }

  function getLoanableAmount(address token, uint256 lockExpiration) public returns (uint256 loanableAmount) {
    uint256 currentWeek = getCurrentWeekTimestamp();
    uint256 maxExpirationDate = _baseExpiration.add(_maxExpiration);
    uint256 loanableAmount;

    while (currentWeek <= lastExpiration && currentWeek <= lockExpiration) {
      loanableAmount = amountsLockedByExpirationPerToken[token][currentWeek];
      currentWeek = currentWeek.add(_expirationIncrement);
    }
  }

  function getEquivalentCollateral(address token, uint256 amount, address collateralToken) public returns (uint256 collateralRequired) {
    uint256 tokenPrice = priceOracle.getAssetPrice(token);
    uint256 collateralPrice = priceOracle.getAssetPrice(collateralToken);
    uint256 collateralRequired = amount.mul(tokenPrice).div(collateralPrice);
  }

  function _unlockAmounts(address token, address denominator, uint256 amountToken, uint256 amountDenominator) internal {
    UserDeposit[] storage depositsForUser = depositsByUser[msg.sender];
    uint256 unlockedToken;
    uint256 unlockedDenominator;

    for (uint256 i = 0; i < depositsForUser.length; i++) {
      UserDeposit memory deposit = depositsForUser[i];

      if (unlockedToken >= amountToken && unlockedDenominator >= amountDenominator) continue;

      if (deposit.lockExpiration <= block.timestamp) {
        uint256 tokenDiff = amountToken.sub(unlockedToken);
        uint256 tokenUnlocked = deposit.amountToken > tokenDiff ? tokenDiff : deposit.amountToken;
        unlockedToken = unlockedToken.add(tokenUnlocked);

        uint256 denomDiff = amountToken.sub(unlockedDenominator);
        uint256 denomUnlocked = deposit.amountDenominator > denomDiff ? denomDiff : deposit.amountDenominator;
        unlockedDenominator = unlockedDenominator.add(denomUnlocked);

        uint256 tokenLocked = amountsLockedByExpirationPerToken[token][deposit.lockExpiration];
        uint256 denomLocked = amountsLockedByExpirationPerToken[denominator][deposit.lockExpiration];

        tokenLocked = tokenLocked.sub(tokenUnlocked);
        denomLocked = denomLocked.sub(denomUnlocked);

        if (tokenLocked == 0 && denomLocked == 0) {
          delete depositsForUser[i];
        }
      }
    }
  }

  function deposit(address token, address denominator, uint256 amountToken, uint256 amountDenominator, uint256 lockExpiration) external {
    IERC20(token).safeTransferFrom(msg.sender, this, amountToken);
    IERC20(denominator).safeTransferFrom(msg.sender, this, amountDenominator);

    amountsLockedByExpirationPerToken[token][lockExpiration] = amountsLockedByExpirationPerToken[token][lockExpiration].add(amountToken);
    amountsLockedByExpirationPerToken[denominator][lockExpiration] = amountsLockedByExpirationPerToken[denominator][lockExpiration].add(amountDenominator);
    
    UserDeposit[] storage depositsForUser = depositsByUser[msg.sender];

    depositsForUser.push({ user: msg.sender, token: token, denominator: denominator, amountToken: amountToken, amountDenominator: amountDenominator, lockExpiration: lockExpiration });

    emit Deposit(msg.sender, token, denominator, lockExpiration, amountToken, amountDenominator);
  }

  function withdraw(address token, address denominator, uint256 amountToken, uint256 amountDenominator) external {
    _unlockAmounts(token, denominator, amountToken, amountDenominator);

    IERC20(token).safeTransferFrom(this, msg.sender, amountToken);
    IERC20(denominator).safeTransferFrom(this, msg.sender, amountDenominator);

    emit Withdraw(msg.sender, token, denominator, amountToken, amountDenominator);
  }

  function borrow(address token, uint256 amountToken, address collateralToken, uint256 amountCollateral, uint256 lockExpiration) external {
    uint256 loanableAmount = getLoanableAmount(token, lockExpiration);
    uint256 collateralRequired = getEquivalentCollateral(token, amountToken, collateralToken);

    // We need to set which tokens will be allowed as collateral

    require(loanableAmount >= amount, "Amount too high.");
    require(_whitelistedBorrowContracts.contains(msg.sender), "Borrow not whitelisted.");
    require(collateralRequired <= amountCollateral, "Not enough collateral.");

    uint256 tokenPrice = priceOracle.getAssetPrice(token);

    Loan loan = new Loan(msg.sender, token, amountToken, collateralToken, amountCollateral, tokenPrice, lockExpiration);

    IERC20(token).safeTransferFrom(this, msg.sender, amountToken);
    IERC20(collateralToken).safeTransferFrom(msg.sender, this, amountCollateral);

    bytes32 hash = getLoanHash(loan);

    loansOutstanding[hash] = loan;

    emit Borrow(hash, msg.sender, token, lockExpiration, amount);
  }

  function repayLoan(Loan memory loan, uint256 amount) external {
    bytes32 hash = getLoanHash(loan);
    repay(hash, amount);
  }

  function repay(bytes32 hash, uint256 amount) public {
    Loan storage loan = loansOutstanding[hash];

    uint256 collateralOut = getEquivalentCollateral(token, amountToken, collateralToken);

    IERC20(loan.token).safeTransferFrom(msg.sender, this, amount);

    loan.amountOutstanding = loan.amountOutstanding.sub(amount);

    if (loan.amountOutstanding <= 0) {
      collateralOut = loan.collateralHeld;

      delete loansOutstanding[hash];
    }

    IERC20(loan.collateralToken).safeTransferFrom(this, msg.sender, collateralOut);

    loan.collateralHeld = loan.collateralHeld.sub(collateralOut);

    emit RepayLoan(hash, msg.sender, loan.token, amount);
  }

  function liquidateLoan(bytes32 hash, uint256 amount) external {
    bytes32 hash = getLoanHash(loan);
    liquidate(hash, amount);
  }

  function checkCollateralizationLevel(Loan memory loan) public returns (bool isCollateralized) {
    uint256 collateralPrice = priceOracle.getAssetPrice(loan.collateralToken);
    uint256 percentCollateralized = loan.collateralHeld.mul(inverseBasisPoint).mul(collateralPrice).div(loan.amountOutstanding).mul(loan.tokenPrice);
    bool isCollateralized = percentCollateralized >= _requiredCollaterizationPercent;
  }

  function liquidate(bytes32 hash, uint256 collateralAmount, address router) public {
    Loan storage loan = loansOutstanding[hash];

    // Do we want to enable the following maximum liquidation percentage?
    // It limits the amount of collateral that can be liquidated at a single time.
    // The intent is to prevent liquidating collateral as much as possible.
    // However, it could have unintended consequences w/ our platform.

    // require(collateralHeld.mul(inverseBasisPoint).div(collateralAmount) >= _maxPercentLiquidated, "Too much liquidated.");

    // TODO: Allow loan to be liquidated if it's past the lockExpiration date

    require(!checkCollateralizationLevel(loan), "Loan is not under-collateralized.");
    require(_whitelistedRouterContracts.contains(router), "Router not whitelisted.");

    _liquidateCollateral(router, loan.collateralToken, loan.token, collateralAmount);

    uint256 rewardFee = collateralAmount.mul(inverseBasisPoint).div(_liquidatorReward);

    IERC20(loan.collateralToken).safeTransferFrom(this, msg.sender, rewardFee);

    if (loan.collateralHeld == 0) {
      delete loansOutstanding[hash];
    }

    emit LiquidateLoan(hash, msg.sender, loan.token, collateralAmount, rewardFee);
  }

  function writeOption(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium, address referrer) external {
    require(_whitelistedWriterContracts.contains(msg.sender), "Writer not whitelisted.");

    // Should there be a limit to the amount we allow each contract to have outstanding?
    // We currently don't track who the contracts are outstanding to, so would need to update.
    // Would also need to set some standard rules for how much each contract can write.

    uint256 outstanding = optionsOutstanding[optionContract][optionId];

    outstanding = oustanding.add(amount);

    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);
    IPremiaOption.OptionWriteArgs memory writeArgs = IPremiaOption.OptionWriteArgs({
        amount: amount,
        token: data.token,
        strikePrice: data.strikePrice,
        expiration: data.expiration,
        isCall: data.isCall
    });

    // Should there be an oracle here used to determine the premium, or do we trust all whitelisted contracts premium quotes?

    IERC20(premiumToken).safeTransferFrom(msg.sender, this, amountPremium);
    IPremiaOption(optionContract).writeOption(option.token, writeArgs, referrer);
    IPremiaOption(optionContract).safeTransferFrom(this, msg.sender, optionId, amount, 0x0);

    emit WriteOption(msg.sender, optionContract, optionId, amount, premiumToken, amountPremium);
  }

  function unwindOption(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 amountPremium) external {
    require(_whitelistedWriterContracts.contains(msg.sender), "Writer not whitelisted.");

    // I think we want to update this function to support exercising of ITM options.
    // I.e. "unwind" the option by exercising ITM for whatever it's worth
    // Or if it's not ITM, sell it to the pool for some premium, and the pool will cancel it

    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);

    if (data.expiration > block.timestamp) {
      IPremiaOption(optionContract).withdraw(optionId);

      // In this case, we might withdraw both the collateral token and the underlying token.
      // If we withdraw both, do we want to sell the collateral token at this time?
      // Or should we just keep both and save on trading fees + slippage?
    } else {
      IPremiaOption(optionContract).cancelOptionFrom(msg.sender, optionId, amount);
    }

    uint256 outstanding = optionsOutstanding[optionContract][optionId];

    outstanding = oustanding.sub(amount);

    // Should there be an oracle here used to determine the premium, or do we trust all whitelisted contracts premium quotes?

    IERC20(premiumToken).safeTransferFrom(this, msg.sender, amountPremium);

    emit UnwindOption(msg.sender, optionContract, optionId, amount);
  }

  function unlockCollateralFromOption(address optionContract, uint256 optionId, uint256 amount) external {
    IPremiaOption.OptionData memory data = IPremiaOption(optionContract).optionData(optionId);

    require(data.expiration > block.timestamp, "Option is not expired yet.");

    IPremiaOption(optionContract).withdraw(optionId);

    // In this case, we might withdraw both the collateral token and the underlying token.
    // If we withdraw both, do we want to sell the collateral token at this time?
    // Or should we just keep both and save on trading fees + slippage?

    uint256 outstanding = optionsOutstanding[optionContract][optionId];

    outstanding = oustanding.sub(amount);

    // Reward unlocker for unlocking the collateral in the option

    emit UnlockCollateral(msg.sender, optionContract, optionId, amount);
  }

  /// @notice Convert collateral back into original tokens
  /// @param router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
  /// @param token The token to swap collateral to
  /// @param collateralToken The token to swap from
  function _liquidateCollateral(IUniswapV2Router02 router, address collateralToken, address token, uint256 amountCollateral) internal {
    require(_whitelistedRouterContracts.contains(address(router)), "Router not whitelisted.");

    IERC20(collateralToken).safeIncreaseAllowance(address(router), amountCollateral);

    address weth = router.WETH();
    address[] memory path = customPath[collateralToken][token];

    if (path.length == 0) {
      path = new address[](2);
      path[0] = collateralToken;
      path[1] = weth;
    }

    path[path.length] = token;

    router.swapExactTokensForTokens(
      amountCollateral,
      0,
      path,
      this,
      block.timestamp.add(60)
    );
  }
}