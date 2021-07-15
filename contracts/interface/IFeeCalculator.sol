// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFeeCalculator {
    enum FeeType {
        Write,
        Exercise,
        Maker,
        Taker,
        FlashLoan
    }

    function writeFee() external view returns (uint256);

    function exerciseFee() external view returns (uint256);

    function flashLoanFee() external view returns (uint256);

    function makerFee() external view returns (uint256);

    function takerFee() external view returns (uint256);

    function getFee(address _user, FeeType _feeType)
        external
        view
        returns (uint256);

    function getFeeAmount(
        address _user,
        uint256 _amount,
        FeeType _feeType
    ) external view returns (uint256);

    function getFeeAmountWithDiscount(address _user, uint256 _baseFee)
        external
        view
        returns (uint256);
}
