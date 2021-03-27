// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';
import "../interface/IPremiaPoolController.sol";

contract PremiaAMM is Ownable, IPoolControllerChild {
  using SafeERC20 for IERC20;

  enum SaleSide {Buy, Sell}

  // The oracle used to get black scholes prices on chain.
  IBlackScholesPriceGetter public blackScholesOracle;

  IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  uint256 public blackScholesWeight = 5e3; // 500 = 50%
  uint256 public constantProductWeight = 5e3; // 500 = 50%

  uint256 constant _inverseBasisPoint = 1e4;

  IPremiaPoolController public controller;

  ////////////
  // Events //
  ////////////

  event Bought(address indexed user, address indexed optionContract, uint256 indexed optionId, uint256 amount, address premiumToken, uint256 optionPrice);
  event Sold(address indexed user, address indexed optionContract, uint256 indexed optionId, uint256 amount, address premiumToken, uint256 optionPrice);
  event ControllerUpdated(address indexed newController);

  //////////////////////////////////////////////////
  //////////////////////////////////////////////////
  //////////////////////////////////////////////////

  ///////////
  // Admin //
  ///////////

  function upgradeController(address _newController) external override {
    require(msg.sender == owner() || msg.sender == address(controller), "Not owner or controller");
    controller = IPremiaPoolController(_newController);
    emit ControllerUpdated(_newController);
  }

  //////////////////////////////////////////////////
  //////////////////////////////////////////////////
  //////////////////////////////////////////////////


  /// @notice Set new weights for pricing function, total must be 1,000
  /// @param _blackScholesWeight Black scholes weighting
  /// @param _constantProductWeight Weighting based on reserves
  function setPriceWeights(IPremiaPoolController _controller, uint256 _blackScholesWeight, uint256 _constantProductWeight) external onlyOwner {
    require(_blackScholesWeight + _constantProductWeight == _inverseBasisPoint);
    controller = _controller;
    blackScholesWeight = _blackScholesWeight;
    constantProductWeight = _constantProductWeight;
  }

  function getCallReserves(address _optionContract, uint256 _optionId) external view returns (uint256) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getCallReserves(data.token, data.expiration);
  }

  function _getCallReserves(address _token, uint256 _expiration) internal view returns (uint256) {
    uint256 reserveAmount;
    IPremiaLiquidityPool[] memory callPools = controller.getCallPools();
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      reserveAmount = reserveAmount + pool.getWritableAmount(_token, _expiration);
    }

    return reserveAmount;
  }

  function getPutReserves(address _optionContract, uint256 _optionId) external view returns (uint256 reserveAmount) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getPutReserves(IPremiaOption(_optionContract).denominator(), data.expiration);
  }

  function _getPutReserves(address _denominator, uint256 _expiration) internal view returns (uint256) {
    uint256 reserveAmount;
    IPremiaLiquidityPool[] memory putPools = controller.getPutPools();
    for (uint256 i = 0; i < putPools.length; i++) {
      IPremiaLiquidityPool pool = putPools[i];
      reserveAmount = reserveAmount + pool.getWritableAmount(_denominator, _expiration);
    }

    return reserveAmount;
  }

  function getCallMaxBuy(address _optionContract, uint256 _optionId) external view returns (uint256) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getCallMaxBuy(data.token, data.expiration);
  }

  function _getCallMaxBuy(address _token, uint256 _expiration) internal view returns (uint256) {
    uint256 maxBuy;
    IPremiaLiquidityPool[] memory callPools = controller.getCallPools();
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      uint256 reserves = pool.getWritableAmount(_token, _expiration);

      if (reserves > maxBuy) {
        maxBuy = reserves; 
      }
    }

    return maxBuy;
  }

  function getCallMaxSell(address _optionContract, uint256 _optionId) external view returns (uint256) {
    IPremiaLiquidityPool[] memory callPools = controller.getCallPools();
    
    uint256 maxSell;
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      uint256 reserves = pool.getUnwritableAmount(_optionContract, _optionId);

      if (reserves > maxSell) {
        maxSell = reserves; 
      }
    }

    return maxSell;
  }

  function getPutMaxBuy(address _optionContract, uint256 _optionId) external view returns (uint256) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getPutMaxBuy(data.token, data.expiration);
  }

  function _getPutMaxBuy(address _token, uint256 _expiration) internal view returns (uint256) {
    uint256 maxBuy;
    IPremiaLiquidityPool[] memory putPools = controller.getPutPools();
    for (uint256 i = 0; i < putPools.length; i++) {
      IPremiaLiquidityPool pool = putPools[i];
      uint256 reserves = pool.getWritableAmount(_token, _expiration);

      if (reserves > maxBuy) {
        maxBuy = reserves; 
      }
    }

    return maxBuy;
  }

  function getPutMaxSell(address _optionContract, uint256 _optionId) external view returns (uint256) {
    IPremiaLiquidityPool[] memory putPools = controller.getPutPools();

    uint256 maxSell;
    for (uint256 i = 0; i < putPools.length; i++) {
      IPremiaLiquidityPool pool = IPremiaLiquidityPool(putPools[i]);
      uint256 reserves = pool.getUnwritableAmount(_optionContract, _optionId);

      if (reserves > maxSell) {
        maxSell = reserves; 
      }
    }

    return maxSell;
  }

  function _getWeightedBlackScholesPrice(address _token, address _denominator, uint256 _strikePrice, uint256 _expiration, uint256 _amountIn, address _premiumToken)
    internal view returns (uint256) {
      uint256 blackScholesPriceInEth = blackScholesOracle.getBlackScholesEstimate(_token, _denominator, _strikePrice, _expiration, _amountIn);
      uint256 ethPrice = blackScholesOracle.getAssetPrice(address(WETH));
      uint256 premiumTokenPrice = blackScholesOracle.getAssetPrice(_premiumToken);
      uint256 blackScholesPrice = ethPrice * uint256(1e12) / premiumTokenPrice * blackScholesPriceInEth / uint256(1e12);
      return blackScholesPrice * _amountIn * _inverseBasisPoint / blackScholesWeight;
  }

  function priceOption(IPremiaOption _optionContract, uint256 _optionId, SaleSide _side, uint256 _amount, address _premiumToken) external view returns (uint256 optionPrice) {
    IPremiaOption.OptionData memory data = _optionContract.optionData(_optionId);
    return _priceOption(data.token, _optionContract.denominator(), data.strikePrice, data.expiration, data.isCall, _side, _amount, _premiumToken);
  }

  function _priceOption(address _token, address _denominator, uint256 _strikePrice, uint256 _expiration, bool _isCall, SaleSide _side, uint256 _amount, address _premiumToken)
    internal view returns (uint256) {
      uint256 amountIn = _isCall ? _amount : _amount * _strikePrice;
      uint256 weightedBsPrice = _getWeightedBlackScholesPrice(_token, _denominator, _strikePrice, _expiration, amountIn, _premiumToken);

      uint256 xt0 = _getCallReserves(_token, _expiration);
      uint256 yt0 = _getPutReserves(_denominator, _expiration);
      uint256 k = xt0 * yt0;

      uint256 xt1;
      uint256 yt1;
      uint256 price;

      if (_side == SaleSide.Buy) {
        if (_isCall) {
          // User is Buying Call
          xt1 = xt0 - amountIn;
          price = weightedBsPrice + (k / xt1 * _inverseBasisPoint / constantProductWeight);
          yt1 = yt0 + price;
        } else {
          // User is Buying Put
          yt1 = yt0 - amountIn;
          price = weightedBsPrice + (k / yt1 * _inverseBasisPoint / constantProductWeight);
        }
      } else {
        if (_isCall) {
          // User is Selling Call
          yt1 = yt0 - amountIn;
          price = weightedBsPrice + (k / yt1 * _inverseBasisPoint / constantProductWeight);
        } else {
          // User is Selling Put
          xt1 = xt0 - amountIn;
          price = weightedBsPrice + (k / xt1 * _inverseBasisPoint / constantProductWeight);
        }
      }

      require(xt1 > 0 && yt1 > 0 && xt1 < k && yt1 < k, "Trade too large.");

      return price;
  }

  function _getLiquidityPool(address _token, address _denominator, uint256 _expiration, bool _isCall, uint256 _amount) internal view returns (IPremiaLiquidityPool) {
    IPremiaLiquidityPool[] memory liquidityPools = _isCall ? controller.getCallPools() : controller.getPutPools();

    for (uint256 i = 0; i < liquidityPools.length; i++) {
      IPremiaLiquidityPool pool = liquidityPools[i];
      uint256 amountAvailable = pool.getWritableAmount(_isCall ? _token : _denominator, _expiration);

      if (amountAvailable >= _amount && address(pool) != address(msg.sender)) {
        return pool;
      }
    }

    revert("Not enough liquidity");
  }

  function buy(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _maxPremiumAmount, address _referrer) external {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    IPremiaLiquidityPool liquidityPool = _getLiquidityPool(data.token, IPremiaOption(_optionContract).denominator(), data.expiration, data.isCall, _amount);

    uint256 optionPrice = _priceOption(data.token, IPremiaOption(_optionContract).denominator(), data.strikePrice, data.expiration, data.isCall, SaleSide.Buy, _amount, _premiumToken);

    require(optionPrice >= _maxPremiumAmount, "Price too high.");

    IERC20(_premiumToken).safeTransferFrom(msg.sender, address(liquidityPool), optionPrice);

    // The pool needs to check that the option contract is whitelisted
    liquidityPool.writeOptionFor(msg.sender, _optionContract, _optionId, _amount, _premiumToken, optionPrice, _referrer);
    emit Bought(msg.sender, _optionContract, _optionId, _amount, _premiumToken, optionPrice);
  }

  function sell(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _minPremiumAmount) external {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    IPremiaLiquidityPool liquidityPool = _getLiquidityPool(data.token, IPremiaOption(_optionContract).denominator(), data.expiration, data.isCall, _amount);

    uint256 optionPrice = _priceOption(data.token, IPremiaOption(_optionContract).denominator(), data.strikePrice, data.expiration, data.isCall, SaleSide.Sell, _amount, _premiumToken);

    require(optionPrice <= _minPremiumAmount, "Price too low.");

    // The pool needs to check that the option contract is whitelisted
    liquidityPool.unwindOptionFor(msg.sender, _optionContract, _optionId, _amount);
    IERC20(_premiumToken).safeTransferFrom(address(liquidityPool), msg.sender, optionPrice);
    emit Sold(msg.sender, _optionContract, _optionId, _amount, _premiumToken, optionPrice);
  }
}