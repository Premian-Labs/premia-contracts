// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';
import '@solidstate/contracts/token/ERC20/ERC20.sol';
import '@solidstate/contracts/token/ERC20/IERC20.sol';
import '@solidstate/contracts/token/ERC1155/ERC1155Base.sol';

import '../pair/Pair.sol';
import './PoolStorage.sol';

import { ABDKMath64x64 } from '../libraries/ABDKMath64x64.sol';
import { OptionMath } from "../libraries/OptionMath.sol";

/**
 * @title Openhedge option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is OwnableInternal, ERC20, ERC1155Base {
  using ABDKMath64x64 for int128;

  /**
   * @notice get address of PairProxy contract
   * @return pair address
   */
  function getPair () external view returns (address) {
    return PoolStorage.layout().pair;
  }

  /**
   * @notice get price of option contract
   * @param amount size of option contract
   * @param strikePrice option strike price
   * @param maturity timestamp of option maturity
   * @return price price of option contract
   * @return cLevel C-Level after purchase
   */
  function quote (
    uint amount,
    uint192 strikePrice,
    uint64 maturity
  ) public view returns (uint price, int128 cLevel) {
    require(maturity > block.timestamp, 'Pool: expiration must be in the future');
    // TODO: calculate

    PoolStorage.Layout storage l = PoolStorage.layout();

    uint volatility = Pair(l.pair).getVolatility();

    uint liquidity = l.liquidity;
    cLevel = OptionMath.calculateCLevel(l.cLevel, liquidity, liquidity - amount, ABDKMath64x64.ONE_64x64);
  }

  /**
   * @notice TODO
   */
  function valueOf (
    uint tokenId,
    uint amount
  ) public view returns (uint) {
    (uint192 strikePrice, uint64 maturity) = _parametersFor(tokenId);

    // TODO: get spot price now or at maturity
    uint spotPrice;

    if (strikePrice > spotPrice) {
      return (strikePrice - spotPrice) * amount;
    } else {
      return 0;
    }
  }

  /**
   * @notice deposit underlying currency, underwriting puts of that currency with respect to base currency
   * @param amount quantity of underlying currency to deposit
   * @return share of pool granted
   */
  function deposit (
    uint amount
  ) external returns (uint share) {
    // TODO: convert ETH to WETH if applicable
    // TODO: set lockup period

    PoolStorage.Layout storage l = PoolStorage.layout();

    IERC20(l.underlying).transferFrom(msg.sender, address(this), amount);

    // TODO: calculate amount minted
    share = 1;

    _mint(msg.sender, share);

    uint oldLiquidity = l.liquidity;
    uint newLiquidity = oldLiquidity + amount;
    l.cLevel = OptionMath.calculateCLevel(l.cLevel, oldLiquidity, newLiquidity, ABDKMath64x64.ONE_64x64);
    l.liquidity = newLiquidity;
  }

  /**
   * @notice redeem pool share tokens for underlying asset
   * @param share quantity of share tokens to redeem
   * @return amount of underlying asset withdrawn
   */
  function withdraw (
    uint share
  ) external returns (uint amount) {
    // TODO: check lockup period
    // TODO: ensure available liquidity, queue if necessary

    PoolStorage.Layout storage l = PoolStorage.layout();

    _burn(msg.sender, share);

    // TODO: calculate share of pool

    IERC20(l.underlying).transfer(msg.sender, amount);

    uint oldLiquidity = l.liquidity;
    uint newLiquidity = oldLiquidity - amount;
    l.cLevel = OptionMath.calculateCLevel(l.cLevel, oldLiquidity, newLiquidity, ABDKMath64x64.ONE_64x64);
    l.liquidity = newLiquidity;
  }

  /**
   * @notice purchase put option
   * @param amount size of option contract
   * @param strikePrice option strike price
   * @param maturity timestamp of option maturity
   */
  function purchase (
    uint amount,
    uint192 strikePrice,
    uint64 maturity
  ) external returns (uint price) {
    // TODO: convert ETH to WETH if applicable
    // TODO: maturity must be integer number of calendar days
    // TODO: accept minimum price to prevent slippage
    // TODO: reserve liquidity

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 cLevel;
    (price, cLevel) = quote(amount, strikePrice, maturity);
    l.cLevel = cLevel;

    IERC20(l.base).transferFrom(msg.sender, address(this), price);

    _mint(msg.sender, _tokenIdFor(strikePrice, maturity), amount, '');
  }

  /**
   * @notice exercise put option
   * @param tokenId ERC1155 token id
   * @param amount quantity of option contract tokens to exercise
   */
  function exercise (
    uint tokenId,
    uint amount
  ) public {
    uint value = valueOf(tokenId, amount);

    require(value > 0, 'Pool: option must be in-the-money');

    _burn(msg.sender, tokenId, amount);

    IERC20(PoolStorage.layout().underlying).transfer(msg.sender, value);
  }

  /**
   * @notice calculate ERC1155 token id for given option parameters
   * @param strikePrice option strike price
   * @param maturity timestamp of option maturity
   * @return token id
   */
  function _tokenIdFor (
    uint192 strikePrice,
    uint64 maturity
  ) internal pure returns (uint) {
    return (uint256(maturity) << 192) + strikePrice;
  }

  /**
   * @notice derive option strike price and maturity from ERC1155 token id
   * @param tokenId token id
   * @return strikePrice option strike price
   * @return maturity timestamp of option maturity
   */
  function _parametersFor (
    uint tokenId
  ) internal pure returns (uint192 strikePrice, uint64 maturity) {
    strikePrice = uint192(tokenId);
    maturity = uint64(tokenId >> 192);
  }
}
