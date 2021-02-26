// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';

contract PremiaNeutralPool is Ownable {
  using SafeMath for uint256;

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
    address amountOutstanding;
    uint256 lockExpiration;
  }

  struct OptionCredit {
    uint256 optionId;
    uint256 amountOutstanding;
  }

  // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
  uint256 private constant _baseExpiration = 172799;
  // Expiration increment
  uint256 private constant _expirationIncrement = 1 weeks;
  // Max expiration time from now
  uint256 public _maxExpiration = 365 days;
  
  // List of whitelisted contracts that can borrow capital from this pool
  EnumerableSet.AddressSet private _whitelistedBorrowContracts;
  // List of whitelisted contracts that can write options from this pool
  EnumerableSet.AddressSet private _whitelistedWriterContracts;

  mapping(address => UserDeposit[]) public depositsByUser;
  mapping(address => mapping(uint256 => uint256)) public amountsLockedByExpirationPerToken;

  mapping(bytes32 => Loan) public loansOutstanding;
  mapping(address => mapping(uint256 => uint256)) public amountsLoanedByExpirationPerToken;

  mapping(address => mapping(uint256 => OptionCredit)) public optionsOutstanding;

  event Deposit(address indexed user, address indexed token, address indexed denominator, uint256 indexed lockExpiration, uint256 amountToken, uint256 amountDenominator);
  event Withdraw(address indexed user, address indexed token, address indexed denominator, uint256 amountToken, uint256 amountDenominator);
  event Borrow(bytes32 indexed hash, address indexed borrower, address indexed token, uint256 indexed lockExpiration, uint256 amount);
  event RepayLoan(bytes32 indexed hash, address indexed borrower, address indexed token, uint256 indexed amount);
  event LiquidateLoan(bytes32 indexed hash, address indexed borrower, address indexed token, uint256 indexed amount);
  event WriteOption(address indexed writed, address indexed optionContract, uint256 indexed optionId, uint256 indexed amount, address premiumToken, uint256 premium);
  event UnwindOption(address indexed writed, address indexed optionContract, uint256 indexed optionId, uint256 indexed amount);
  event UnlockCollateral(address indexed writed, address indexed optionContract, uint256 indexed optionId, uint256 indexed amount);


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
  
  /// @notice Get the hash of an loan
  /// @param _loan The loan from which to calculate the hash
  /// @return The loan hash
  function getLoanHash(Loan memory _loan) public pure returns(bytes32) {
      return keccak256(abi.encode(_loan));
  }

  function getUnlockableAmounts(address token, address denominator, uint256 amountToken, uint256 amountDenominator) external returns (uint256 unlockableToken, uint256 unlockableDenominator) {
    UserDeposit[] memory depositsForUser = depositsByUser[msg.sender];
    uint256 unlockableToken;
    uint256 unlockableDenominator;

    for (uint256 i = 0; i < depositsForUser.length; i++) {
      UserDeposit deposit = depositsForUser[i];

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

  function _unlockAmounts(address token, address denominator, uint256 amountToken, uint256 amountDenominator) internal {
    UserDeposit[] storage depositsForUser = depositsByUser[msg.sender];
    uint256 unlockedToken;
    uint256 unlockedDenominator;

    for (uint256 i = 0; i < depositsForUser.length; i++) {
      UserDeposit deposit = depositsForUser[i];

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
    // transfer tokens in

    amountsLockedByExpirationPerToken[token][lockExpiration] = amountsLockedByExpirationPerToken[token][lockExpiration].add(amountToken);
    amountsLockedByExpirationPerToken[denominator][lockExpiration] = amountsLockedByExpirationPerToken[denominator][lockExpiration].add(amountDenominator);
    
    UserDeposit[] storage depositsForUser = depositsByUser[msg.sender];

    depositsForUser.push({ user: msg.sender, token: token, denominator: denominator, amountToken: amountToken, amountDenominator: amountDenominator, lockExpiration: lockExpiration });

    emit Deposit(msg.sender, token, denominator, lockExpiration, amountToken, amountDenominator);
  }

  function withdraw(address token, address denominator, uint256 amountToken, uint256 amountDenominator) external {
    _unlockAmounts(token, denominator, amountToken, amountDenominator);

    // transfer tokens out

    emit Withdraw(msg.sender, token, denominator, amountToken, amountDenominator);
  }

  function borrow(address token, uint256 amount, uint256 lockExpiration) external {
    uint256 loanableAmount = getLoanableAmount(token, lockExpiration);

    require(loanableAmount >= amount, "Amount too high.");
    require(_whitelistedBorrowContracts.contains(msg.sender), "Borrow not allowed.");

    Loan loan = new Loan();

    // transfer collateral tokens in
    // transfer borrowed tokens out

    bytes32 hash = getLoanHash(loan);

    emit Borrow(hash, msg.sender, token, lockExpiration, amount);
  }

  function repayLoan(Loan memory loan, uint256 amount) external {
    bytes32 hash = getLoanHash(loan);
    repay(hash, amount);
  }

  function repay(bytes32 hash, uint256 amount) public {
    Loan loan = loansOutstanding[hash];

    // transfer borrowed tokens in

    loan.amountOutstanding = loan.amountOutstanding.sub(amount);

    if (loan.amountOutstanding <= 0) {
      delete loansOutstanding[hash];
    }

    // transfer collateral tokens out

    emit RepayLoan(hash, msg.sender, loan.token, amount);
  }

  function liquidateLoan(bytes32 hash, uint256 amount) external {
    bytes32 hash = getLoanHash(loan);
    liquidate(hash, amount);
  }

  function liquidate(bytes32 hash, uint256 amount) public {
    Loan loan = loansOutstanding[hash];

    // sell collateral
    // transfer finder's fee to liquidater

    emit LiquidateLoan(hash, msg.sender, loan.token, amount);
  }

  function writeOption(address optionContract, uint256 optionId, uint256 amount, address premiumToken, uint256 premium) external {
    require(_whitelistedWriterContracts.contains(msg.sender), "Writer not allowed.");

    uint256 outstanding = optionsOutstanding[optionContract][optionId];

    outstanding = oustanding.add(amount);

    // write option
    // transfer option to caller
    // accept payment
  }

  function unwindOption(address optionContract, uint256 optionId, uint256 amount) external {
    require(_whitelistedWriterContracts.contains(msg.sender), "Writer not allowed.");

    uint256 outstanding = optionsOutstanding[optionContract][optionId];

    outstanding = oustanding.sub(amount);
  }

  function unlockCollateral(address optionContract, uint256 optionId) external {

  }
}