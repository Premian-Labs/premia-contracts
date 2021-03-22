// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './PremiaLiquidityPool.sol';

contract PremiaShortUnderlyingPool is PremiaLiquidityPool {
  // token address => queue index => loan hash
  mapping(address => mapping(uint256 => bytes32)) loansTaken;
  // token address => index
  mapping(address => uint256) loanQueuesFirst;
  // token address => index
  mapping(address => uint256) loanQueuesLast;

  constructor(address _controller) PremiaLiquidityPool(_controller) {}

  function _enqueueLoan(Loan memory _loan) internal returns (bytes32) {
      bytes32 hash = getLoanHash(_loan);
      
      loanQueuesLast[_loan.token] += 1;
      loansTaken[_loan.token][loanQueuesLast[_loan.token]] = hash;

      return hash;
  }

  function _dequeueLoanHash(address _token) internal returns (bytes32) {
      uint256 first = loanQueuesFirst[_token];
      uint256 last = loanQueuesLast[_token];

      require(last >= first);  // non-empty queue

      bytes32 hash = loansTaken[_token][first];
      delete loansTaken[_token][first];

      loanQueuesFirst[_token] += 1;

      return hash;
  }

  function writeOptionFor(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) public override {
    super.writeOptionFor(_receiver, _optionContract, _optionId, _amount, _premiumToken, _amountPremium, _referrer);
    
    IPremiaOption optionContract = IPremiaOption(_optionContract);
    IPremiaOption.OptionData memory data = optionContract.optionData(_optionId);
    PremiaLiquidityPool loanPool = _getLoanPool(data, optionContract, _amount);

    address collateralToken = optionContract.denominator();
    uint256 amountToBorrow = _getAmountToBorrow(_amount, collateralToken, data.token);

    Loan memory loan = loanPool.borrow(data.token, amountToBorrow, collateralToken, _amount, data.expiration);
    _swapTokensIn(data.token, collateralToken, amountToBorrow);

    bytes32 hash = _enqueueLoan(loan);
    loansCreated[hash] = loan;
  }

  function unwindOptionFor(address _sender, address _optionContract, uint256 _optionId, uint256 _amount) public override {
    super.unwindOptionFor(_sender, _optionContract, _optionId, _amount);
  }

  function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) public override {
    super.unlockCollateralFromOption(_optionContract, _optionId, _amount);
  }

  function _postLiquidate(Loan memory loan, uint256 _collateralAmount) internal override {}

  function _postWithdrawal(address _optionContract, uint256 _optionId, uint256 _amount, uint256 _tokenWithdrawn, uint256 _denominatorWithdrawn)
    internal override {
    IPremiaOption optionContract = IPremiaOption(_optionContract);
    IPremiaOption.OptionData memory data = optionContract.optionData(_optionId);

    address collateralToken = optionContract.denominator();
    uint256 amountOut = _swapTokensIn(collateralToken, data.token, _denominatorWithdrawn);

    uint256 amountLeft = amountOut + _tokenWithdrawn;
    while (amountLeft > 0) {
      bytes32 hash = _dequeueLoanHash(collateralToken);
      Loan memory loan = loansCreated[hash];
      PremiaLiquidityPool loanPool = PremiaLiquidityPool(loan.lender);

      uint256 amountRepaid = loanPool.repay(hash, amountLeft);

      amountLeft -= amountRepaid;
    }
  }
}