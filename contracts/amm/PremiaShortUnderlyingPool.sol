// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './PremiaLiquidityPool.sol';
import './AMMStruct.sol';
import '../interface/IPremiaAMM.sol';
import '../interface/IPremiaOption.sol';

contract PremiaShortUnderlyingPool is PremiaLiquidityPool {
    // token address => queue index => loan hash
    mapping(address => mapping(uint256 => Loan)) loansTaken;
    // token address => index
    mapping(address => uint256) loanQueuesFirst;
    // token address => index
    mapping(address => uint256) loanQueuesLast;

    constructor(IPremiaAMM _controller, IPriceOracleGetter _priceOracle, ILendingRateOracleGetter _lendingRateOracle)
        PremiaLiquidityPool(_controller, false, _priceOracle, _lendingRateOracle) {}

    function _enqueueLoan(Loan memory _loan) internal {
        loanQueuesLast[_loan.token] += 1;
        loansTaken[_loan.token][loanQueuesLast[_loan.token]] = _loan;
    }

    function _dequeueLoan(address _token) internal returns (Loan memory) {
        uint256 first = loanQueuesFirst[_token];
        uint256 last = loanQueuesLast[_token];

        require(last >= first);    // non-empty queue

        Loan memory loan = loansTaken[_token][first];

        delete loansTaken[_token][first];

        loanQueuesFirst[_token] += 1;

        return loan;
    }

    function _afterBuyOption(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, uint256 _amountPremium, address _referrer) internal override {
        IPremiaOption optionContract = IPremiaOption(_optionContract);
        address collateralToken = optionContract.denominator();

        IPremiaOption.OptionData memory data = optionContract.optionData(_optionId);
        PremiaLiquidityPool loanPool = PremiaLiquidityPool(address(_getLoanPool(data.token, collateralToken, data.expiration, data.isCall, _amount)));

        uint256 amountToBorrow = _getAmountToBorrow(_amount, collateralToken, data.token);

        // ToDo : Approve token transfer
        Loan memory loan = loanPool.borrow(AMMStruct.TokenPair(data.token, collateralToken), amountToBorrow, _amount, data.expiration);
        _swapTokensIn(data.token, collateralToken, amountToBorrow);
        _enqueueLoan(loan);
    }

    function _afterSellOption(address _optionContract, uint256 _optionId, uint256 _amount, uint256 _tokenWithdrawn, uint256 _denominatorWithdrawn)
        internal override {
        IPremiaOption optionContract = IPremiaOption(_optionContract);
        IPremiaOption.OptionData memory data = optionContract.optionData(_optionId);

        address collateralToken = optionContract.denominator();
        uint256 amountOut = _swapTokensIn(collateralToken, data.token, _denominatorWithdrawn);

        uint256 amountLeft = amountOut + _tokenWithdrawn;
        while (amountLeft > 0) {
            Loan memory loan = _dequeueLoan(collateralToken);
            PremiaLiquidityPool loanPool = PremiaLiquidityPool(loan.lender);

            uint256 amountRepaid = loanPool.repayLoan(loan, amountLeft);

            amountLeft -= amountRepaid;
        }
    }
}