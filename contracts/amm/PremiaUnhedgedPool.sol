// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './PremiaLiquidityPool.sol';
import '../interface/IPremiaAMM.sol';

contract PremiaUnhedgedPool is PremiaLiquidityPool {
    constructor(IPremiaAMM _controller, IPriceOracleGetter _priceOracle, ILendingRateOracleGetter _lendingRateOracle)
        PremiaLiquidityPool(_controller, _priceOracle, _lendingRateOracle) {}

//    function getLoanableAmount(address _token, uint256 _lockExpiration) public override returns (uint256) {
//        return 0;
//    }
//
//    function borrow(address _token, uint256 _amountToken, address _collateralToken, uint256 _amountCollateral, uint256 _lockExpiration) external override returns (Loan memory) {
//        revert();
//    }
//
//    function repay(bytes32 _hash, uint256 _amount) public override returns (uint256) {
//        revert();
//    }
//
//    function liquidate(bytes32 _hash, uint256 _collateralAmount) public override {
//        revert();
//    }
}