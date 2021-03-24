// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './PremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IPremiaAMM.sol';
import '../interface/IPremiaPoolController.sol';

contract PremiaLongStablecoinPool is PremiaLiquidityPool {
  IPremiaAMM amm;

  constructor(IPremiaPoolController _controller, IPriceOracleGetter _priceOracle, ILendingRateOracleGetter _lendingRateOracle)
    PremiaLiquidityPool(_controller, _priceOracle, _lendingRateOracle) {}

  function getLoanableAmount(address _token, uint256 _lockExpiration) public override returns (uint256) {
    return 0;
  }

  function writeOptionFor(address _receiver, address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _amountPremium, address _referrer) public override {
    super.writeOptionFor(_receiver, _optionContract, _optionId, _amount, _premiumToken, _amountPremium, _referrer);
    amm.buy(_optionContract, _optionId, _amount, _premiumToken, _amountPremium, _referrer);
  }

  function unwindOptionFor(address _sender, address _optionContract, uint256 _optionId, uint256 _amount) public override {
    super.unwindOptionFor(_sender, _optionContract, _optionId, _amount);
  }

  function unlockCollateralFromOption(address _optionContract, uint256 _optionId, uint256 _amount) public override {
    super.unlockCollateralFromOption(_optionContract, _optionId, _amount);
  }

  function _postWithdrawal(address _optionContract, uint256 _optionId, uint256 _amount, uint256 _tokenWithdrawn, uint256 _denominatorWithdrawn)
    internal override {
    IPremiaOption optionContract = IPremiaOption(_optionContract);
    IPremiaOption.OptionData memory data = optionContract.optionData(_optionId);

    _swapTokensIn(data.token, optionContract.denominator(), _tokenWithdrawn);
  }
}