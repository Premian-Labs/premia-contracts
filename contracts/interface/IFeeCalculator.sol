// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFeeCalculator {
    enum FeeType {Write, Exercise, Maker, Taker, FlashLoan}

    function writeFee() external view returns(uint256);
    function exerciseFee() external view returns(uint256);
    function flashLoanFee() external view returns(uint256);

    function referrerFee() external view returns(uint256);
    function referredDiscount() external view returns(uint256);

    function makerFee() external view returns(uint256);
    function takerFee() external view returns(uint256);

    function getFee(address _user, bool _hasReferrer, FeeType _feeType) external view returns(uint256);
    function getFeeAmounts(address _user, bool _hasReferrer, uint256 _amount, FeeType _feeType) external view returns(uint256 _fee, uint256 _feeReferrer);
    function getFeeAmountsWithDiscount(address _user, bool _hasReferrer, uint256 _baseFee) external view returns(uint256 _fee, uint256 _feeReferrer);
}
