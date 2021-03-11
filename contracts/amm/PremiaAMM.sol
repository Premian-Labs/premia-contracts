// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../interface/IPremiaLiquidityPool.sol';
import '../interface/IPremiaOption.sol';
import '../interface/IBlackScholesPriceGetter.sol';

contract PremiaAMM is Ownable {
  using SafeERC20 for IERC20;

  enum SaleSide {Buy, Sell}

  // The oracle used to get black scholes prices on chain.
  IBlackScholesPriceGetter public blackScholesOracle;

  IPremiaLiquidityPool[] public callPools;
  IPremiaLiquidityPool[] public putPools;

  IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  uint256 public blackScholesWeight = 500; // 500 = 50%
  uint256 public constantProductWeight = 500; // 500 = 50%

  uint256 public constant inverseBasisPoint = 1000;

  /// @notice Set new weights for pricing function, total must be 1,000
  /// @param _blackScholesWeight Black scholes weighting
  /// @param _constantProductWeight Weighting based on reserves
  function setPriceWeights(uint256 _blackScholesWeight, uint256 _constantProductWeight) external onlyOwner {
    require(_blackScholesWeight + _constantProductWeight == inverseBasisPoint);
    blackScholesWeight = _blackScholesWeight;
    constantProductWeight = _constantProductWeight;
  }

  function getCallReserves(address _optionContract, uint256 _optionId) public view returns (uint256) {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    return _getCallReserves(data);
  }

  function _getCallReserves(IPremiaOption.OptionData memory _data) internal view returns (uint256) {
    uint256 reserveAmount;
    for (uint256 i = 0; i < callPools.length; i++) {
      IPremiaLiquidityPool pool = callPools[i];
      reserveAmount = reserveAmount + pool.getWritableAmount(_data.token, _data.expiration);
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
      reserveAmount = reserveAmount + pool.getWritableAmount(_optionContract.denominator(), _data.expiration);
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

  function priceOption(IPremiaOption _optionContract, uint256 _optionId, SaleSide _side, uint256 _amount, address _premiumToken)
    public returns (uint256 optionPrice) {
      // TODO: Make this a view
    IPremiaOption.OptionData memory _data = _optionContract.optionData(_optionId);
    return _priceOption(_data, _optionContract, _optionId, _side, _amount, _premiumToken);
  }

  function _priceOption(IPremiaOption.OptionData memory _data, IPremiaOption _optionContract, uint256 _optionId, SaleSide _side, uint256 _amount, address _premiumToken)
    internal returns (uint256) {
    uint256 xt0 = _getCallReserves(_data);
    uint256 yt0 = _getPutReserves(_data, _optionContract);
    uint256 k = xt0 * yt0;

    uint256 amountIn = _data.isCall ? _amount : _amount * _data.strikePrice;
    uint256 blackScholesPriceInEth = blackScholesOracle.getBlackScholesEstimate(_optionContract, _optionId, amountIn);
    uint256 ethPrice = blackScholesOracle.getAssetPrice(address(WETH));
    uint256 premiumTokenPrice = blackScholesOracle.getAssetPrice(_premiumToken);
    uint256 blackScholesPrice = ethPrice * uint256(1e12) / premiumTokenPrice * blackScholesPriceInEth / uint256(1e12);
    uint256 bsPortion = blackScholesPrice * _amount * inverseBasisPoint / blackScholesWeight;
   
    uint256 xt1;
    uint256 yt1;
    uint256 price;

    if (_side == SaleSide.Buy) {
      if (_data.isCall) {
        // User is Buying Call
        xt1 = xt0 - amountIn;
        price = bsPortion + (k / xt1 * inverseBasisPoint / constantProductWeight);
        yt1 = yt0 + price;
      } else {
        // User is Buying Put
        yt1 = yt0 - amountIn;
        price = bsPortion + (k / yt1 * inverseBasisPoint / constantProductWeight);
      }
    } else {
      if (_data.isCall) {
        // User is Selling Call
        yt1 = yt0 - amountIn;
        price = bsPortion + (k / yt1 * inverseBasisPoint / constantProductWeight);
      } else {
        // User is Selling Put
        xt1 = xt0 - amountIn;
        price = bsPortion + (k / xt1 * inverseBasisPoint / constantProductWeight);
      }
    }

    require(xt1 > 0 && yt1 > 0 && xt1 < k && yt1 < k, "Trade too large.");
    
    return price;
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

    uint256 optionPrice = _priceOption(data, IPremiaOption(_optionContract), _optionId, SaleSide.Buy, _amount, _premiumToken);

    require(optionPrice >= _maxPremiumAmount, "Price too high.");

    IERC20(_premiumToken).safeTransferFrom(msg.sender, address(liquidityPool), optionPrice);
    liquidityPool.writeOptionFor(msg.sender, _optionContract, _optionId, _amount, _premiumToken, optionPrice, _referrer);
  }

  function sell(address _optionContract, uint256 _optionId, uint256 _amount, address _premiumToken, uint256 _minPremiumAmount, address _referrer) external {
    IPremiaOption.OptionData memory data = IPremiaOption(_optionContract).optionData(_optionId);
    IPremiaLiquidityPool liquidityPool = _getLiquidityPool(data, IPremiaOption(_optionContract), _amount);

    uint256 optionPrice = _priceOption(data, IPremiaOption(_optionContract), _optionId, SaleSide.Sell, _amount, _premiumToken);

    require(optionPrice <= _minPremiumAmount, "Price too low.");

    liquidityPool.unwindOptionFor(msg.sender, _optionContract, _optionId, _amount, _premiumToken, optionPrice);
    IERC20(_premiumToken).safeTransferFrom(address(liquidityPool), msg.sender, optionPrice);
  }
}