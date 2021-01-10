// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

// Contract used to provide token prices in USD, in order to calculate PremiaUncut reward to give to users.
// Prices will be updated manually every few days, as this use case doesnt really require very accurate price data
interface IFeeCalculator {
    enum FeeType {Write, Exercise, Maker, Taker, FlashLoan}

    function writeFee() external returns(uint256);
    function exerciseFee() external returns(uint256);
    function flashLoanFee() external returns(uint256);

    function referrerFee() external returns(uint256);
    function referredDiscount() external returns(uint256);

    function makerFee() external returns(uint256);
    function takerFee() external returns(uint256);

    function getBaseFee(uint256 _amount, FeeType _feeType) external view returns(uint256);
    function getFees(address _user, bool _hasReferrer, uint256 _amount, FeeType _feeType) external view returns(uint256 _fee, uint256 _feeReferrer);
    function getFeesWithDiscount(address _user, bool _hasReferrer, uint256 _baseFee) external view returns(uint256 _fee, uint256 _feeReferrer);
}
