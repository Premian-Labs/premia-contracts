// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

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

  // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
  uint256 private constant _baseExpiration = 172799;
  // Expiration increment
  uint256 private constant _expirationIncrement = 1 weeks;
  // Max expiration time from now
  uint256 public _maxExpiration = 365 days;
  
  // List of whitelisted pools, which can borrow capital from this pool
  EnumerableSet.AddressSet private _whitelistedBorrowContracts;

  mapping(address => UserDeposit[]) public depositsByUser;
  mapping(address => mapping(uint256 => uint256)) public amountsLockedByExpirationPerToken;

  event Deposit(address indexed user, address indexed token, address indexed denominator, uint256 amountToken, uint256 amountDenominator, uint256 lockExpiration);
  event Withdraw(address indexed user, address indexed token, address indexed denominator, uint256 amountToken, uint256 amountDenominator);
  event LoanCapital(address indexed pool, address indexed token, uint256 indexed amount, uint256 indexed lockExpiration);


  /// @notice Add contract addresses to the list of whitelisted option contracts
  /// @param _addr The list of addresses to add
  function addWhitelistedBorrowContracts(address[] memory _addr) external onlyOwner {
      for (uint256 i=0; i < _addr.length; i++) {
          _whitelistedBorrowContracts.add(_addr[i]);
      }
  }

  /// @notice Remove contract addresses from the list of whitelisted option contracts
  /// @param _addr The list of addresses to remove
  function removeWhitelistedBorrowContracts(address[] memory _addr) external onlyOwner {
      for (uint256 i=0; i < _addr.length; i++) {
          _whitelistedBorrowContracts.remove(_addr[i]);
      }
  }

  /// @notice Get the list of whitelisted option contracts
  /// @return The list of whitelisted option contracts
  function getWhitelistedBorrowContracts() external view returns(address[] memory) {
      uint256 length = _whitelistedBorrowContracts.length();
      address[] memory result = new address[](length);

      for (uint256 i=0; i < length; i++) {
          result[i] = _whitelistedBorrowContracts.at(i);
      }

      return result;
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
      currentWeek = currentWeek.plus(_expirationIncrement);
    }
  }

  function getLoanableAmount(address token, uint256 lockExpiration) public returns (uint256 loanableAmount) {
    uint256 currentWeek = getCurrentWeekTimestamp();
    uint256 maxExpirationDate = _baseExpiration.plus(_maxExpiration);
    uint256 loanableAmount;

    while (currentWeek <= lastExpiration && currentWeek <= lockExpiration) {
      loanableAmount = amountsLockedByExpirationPerToken[token][currentWeek];
      currentWeek = currentWeek.plus(_expirationIncrement);
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
    // transfer tokens

    amountsLockedByExpirationPerToken[token][lockExpiration] = amountsLockedByExpirationPerToken[token][lockExpiration].add(amountToken);
    amountsLockedByExpirationPerToken[denominator][lockExpiration] = amountsLockedByExpirationPerToken[denominator][lockExpiration].add(amountDenominator);
    
    UserDeposit[] storage depositsForUser = depositsByUser[msg.sender];

    depositsForUser.push({ user: msg.sender, token: token, denominator: denominator, amountToken: amountToken, amountDenominator: amountDenominator, lockExpiration: lockExpiration });

    emit Deposit(msg.sender, token, denominator, amountToken, amountDenominator, lockExpiration);
  }

  function withdraw(address token, address denominator, uint256 amountToken, uint256 amountDenominator) external {
    _unlockAmounts(token, denominator, amountToken, amountDenominator);

    // transfer tokens

    emit Withdraw(msg.sender, token, denominator, amountToken, amountDenominator);
  }

  function requestCapital(address token, uint256 amount, uint256 lockExpiration) external {
    uint256 loanableAmount = getLoanableAmount(token, lockExpiration);

    require(loanableAmount >= amount, "Amount too high.");
    require(_whitelistedBorrowContracts.contains(msg.sender), "Borrow not allowed.")

    // transfer tokens

    emit LoanCapital(msg.sender, token, amount, lockExpiration);
  }
}