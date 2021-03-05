// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';

contract PremiaAMM is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // The oracle used to get black scholes prices on chain.
  IBlackScholesPriceGetter public blackScholesOracle;

  IPremiaLiquidityPool[] public callPools;
  IPremiaLiquidityPool[] public putPools;

  uint256 k = 1;

  function getCallReserves(address _optionContract, uint256 _optionId) public view returns (uint256) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getCallReserves(data);
  }

  function _getCallReserves(IPremiaOption.OptionData memory _data) internal view returns (uint256) {
    uint256 reserveAmount;
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      reserveAmount = reserveAmount.add(pool.getWritableAmount(_data.token, _data.expiration));
    }

    return reserveAmount;
  }

  function getPutReserves(address _optionContract, uint256 _optionId) public view returns (uint256 reserveAmount) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getPutReserves(data, IPremiaOption(_optionContract));
  }

  function _getPutReserves(IPremiaOption.OptionData memory _data, IPremiaOption _optionContract) internal view returns (uint256) {
    uint256 reserveAmount;
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      reserveAmount = reserveAmount.add(pool.getWritableAmount(_optionContract.denominator(), _data.expiration));
    }

    return reserveAmount;
  }

  function getCallMaxBuy(address _optionContract, uint256 _optionId) public view returns (uint256) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getCallMaxBuy(data);
  }

  function _getCallMaxBuy(IPremiaOption.OptionData memory _data) internal view returns (uint256) {
    uint256 maxBuy;
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      uint256 reserves = pool.getWritableAmount(_data.token, _data.expiration);

      if (reserves > maxBuy) {
        maxBuy = reserves; 
      }
    }

    return maxBuy;
  }

  function getCallMaxSell(address _optionContract, uint256 _optionId) public view returns (uint256) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getCallMaxSell(_optionId);
  }

  function _getCallMaxSell(uint256 _optionId) internal view returns (uint256) {
    uint256 maxSell;
    // TODO: calculate max sell
    return maxSell;
  }

  function getPutMaxBuy(address _optionContract, uint256 _optionId) public view returns (uint256) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getPutMaxBuy(data, IPremiaOption(_optionContract), _optionId);
  }

  function _getPutMaxBuy(IPremiaOption.OptionData memory _data, IPremiaOption _optionContract, uint256 _optionId) internal view returns (uint256) {
    uint256 maxBuy;
    for (uint256 i = 0; i < putPools.length; i++) {
      IPremiaLiquidityPool pool = putPools[i];
      uint256 reserves = pool.getWritableAmount(_optionContract.denominator(), _data.expiration);

      if (reserves > maxBuy) {
        maxBuy = reserves; 
      }
    }

    return maxBuy;
  }

  function getPutMaxSell(address _optionContract, uint256 _optionId) public view returns (uint256) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getPutMaxSell(data, IPremiaOption(_optionContract), _optionId);
  }

  function _getPutMaxSell(IPremiaOption.OptionData memory _data, IPremiaOption _optionContract, uint256 _optionId) internal view returns (uint256) {
    uint256 maxSell;
    // TODO: calculate max sell
    return maxSell;
  }

  function priceOption(IPremiaOption.OptionData memory _data, IPremiaOption _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken)
    public view returns (uint256 optionPrice) {
    // Source: https://arxiv.org/pdf/2101.02778.pdf (page 5)
    // sum all call reserves + put reserves and plug into the following formula:
    // k = w(t) · (x(t) − a(t)) · y(t)
    // a(t) < x(t), w(t) > 0, x(t) > 0, y(t) > 0
    // where w(t) and a(t) are both functions of the current price,
    // x(t) is the amount of reserves in the call pool
    // y(t) is the amount of reserves in the put pool
    // and k is a constant set at initialization of the pool

    // instantaneous price at any moment can be found through the following:
    // optionPrice = (k / w(t)) *  (1 / (x(t) - a(t))^2 
    // where a(t) = x(t) − (y(t) / p_market(t))
    // and w(t) = (k * p_market(t)) / y(t)^2

    uint256 x_t_0;
    uint256 x_t_1;
    uint256 y_t_0;
    uint256 y_t_1;
    uint256 k_0 = k;

    if (_data.isCall) {
      x_t_0 = _getCallReserves(_data);
      x_t_1 = x_t_0.sub(_amount);
      y_t_0 = _getPutReserves(_data, _optionContract);
      y_t_1 = y_t_0;
    } else {
      x_t_0 = _getCallReserves(_data);
      x_t_1 = x_t_0;
      y_t_0 = _getPutReserves(_data, _optionContract);
      y_t_1 = y_t_0.sub(_amount.mul(_data.strikePrice));
    }

    uint256 p_market_t = blackScholesOracle.getBlackScholesEstimate(address(_optionContract), _optionId);

    uint256 a_t_0 = x_t_0.sub(y_t_0.div(p_market_t));
    uint256 w_t_0 = k_0.mul(p_market_t).div(y_t_0.mul(y_t_0));
    uint256 k_1 = w_t_0.mul(x_t_0.sub(a_t_0)).mul(y_t_0);

    uint256 a_t_1 = x_t_1.sub(y_t_1.div(p_market_t));
    uint256 w_t_1 = k_1.mul(p_market_t).div(y_t_1.mul(y_t_1));

    uint256 x_t_1_diff = x_t_1.sub(a_t_1);

    return k_1.div(w_t_1).mul(uint256(1e12).div(x_t_1_diff.mul(x_t_1_diff))).div(1e12);
  }

  function _priceOptionWithUpdate(IPremiaOption.OptionData memory _data, IPremiaOption _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken) internal returns (uint256) {
    uint256 x_t;
    uint256 y_t;

    if (_data.isCall) {
      x_t = _getCallReserves(_data).sub(_amount);
      y_t = _getPutReserves(_data, _optionContract);
    } else {
      x_t = _getCallReserves(_data);
      y_t = _getPutReserves(_data, _optionContract).sub(_amount.mul(_data.strikePrice));
    }

    _updateKFromReserves(_data, _optionContract, _optionId, _amount, _premiumToken);

    uint256 p_market_t = blackScholesOracle.getBlackScholesEstimate(address(_optionContract), _optionId);
    uint256 a_t = x_t.sub(y_t.div(p_market_t));
    uint256 w_t = k.mul(p_market_t).div(y_t.mul(y_t));

    uint256 x_t_diff = x_t.sub(a_t);

    return k.div(w_t).mul(uint256(1e12).div(x_t_diff.mul(x_t_diff))).div(1e12);
  }

  function _updateKFromReserves(IPremiaOption.OptionData memory _data, IPremiaOption _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken) internal {
    uint256 p_market_t = blackScholesOracle.getBlackScholesEstimate(address(_optionContract), _optionId);
    uint256 x_t = _getCallReserves(_data);
    uint256 y_t = _getPutReserves(_data, _optionContract);
    uint256 a_t = x_t.sub(y_t.div(p_market_t));
    uint256 w_t = k.mul(p_market_t).div(y_t.mul(y_t));

    k = w_t.mul(x_t.sub(a_t)).mul(y_t);
  }

  function _getLiquidityPool(IPremiaOption.OptionData memory _data, IPremiaOption _optionContract, uint256 _amount) internal returns (IPremiaLiquidityPool) {
    IPremiaLiquidityPool[] memory liquidityPools = _data.isCall ? callPools : putPools;

    for (uint256 i = 0; i < liquidityPools.length; i++) {
      IPremiaLiquidityPool pool = liquidityPools[i];
      uint256 amountAvailable = pool.getWritableAmount(_data.isCall ? _data.token : _optionContract.denominator(), _data.expiration);

      if (amountAvailable >= _amount) {
        return pool;
      }
    }

    revert("Not enough liquidity");
  }

  function buy(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _maxPremiumAmount, address _referrer) external {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    IPremiaLiquidityPool liquidityPool = _getLiquidityPool(data, IPremiaOption(_optionContract), _amount);

    uint256 optionPrice = _priceOptionWithUpdate(data, IPremiaOption(_optionContract), _optionId, _amount, _premiumToken);

    require(optionPrice >= _maxPremiumAmount, "Price too high.");

    IERC20(_premiumToken).safeTransferFrom(msg.sender, address(liquidityPool), optionPrice);
    liquidityPool.writeOptionFor(msg.sender, _optionContract, _optionId, _amount, _premiumToken, optionPrice, _referrer);
  }

  function sell(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _minPremiumAmount, address _referrer) external {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    IPremiaLiquidityPool liquidityPool = _getLiquidityPool(data, IPremiaOption(_optionContract), _amount);

    uint256 optionPrice = _priceOptionWithUpdate(data, IPremiaOption(_optionContract), _optionId, _amount, _premiumToken);

    require(optionPrice <= _minPremiumAmount, "Price too low.");

    liquidityPool.unwindOptionFor(msg.sender, _optionContract, _optionId, _amount, _premiumToken, optionPrice);
    IERC20(_premiumToken).safeTransferFrom(address(liquidityPool), msg.sender, optionPrice);
  }
}