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
   * @return c global "c" value after purchase
   */
  function quote (
    uint amount,
    uint192 strikePrice,
    uint maturity
  ) public view returns (uint price, int128 c) {
    // TODO: calculate

    PoolStorage.Layout storage l = PoolStorage.layout();

    uint volatility = Pair(l.pair).getVolatility();

    uint liquidity = l.liquidity;
    c = _calculateC(l.c, liquidity, liquidity - amount);
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
    l.c = _calculateC(l.c, oldLiquidity, newLiquidity);
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
    uint amount;

    IERC20(l.underlying).transfer(msg.sender, amount);

    uint oldLiquidity = l.liquidity;
    uint newLiquidity = oldLiquidity - amount;
    l.c = _calculateC(l.c, oldLiquidity, newLiquidity);
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

    // TODO: reserve liquidity

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 c;
    (price, c) = quote(amount, strikePrice, maturity);
    l.c = c;

    IERC20(l.underlying).transferFrom(msg.sender, address(this), price);

    _mint(msg.sender, _tokenIdFor(strikePrice, maturity), amount, '');
  }

  /**
   * @notice exercise put option
   * @param amount quantity of option contract tokens to exercise
   * @param strikePrice option strike price
   * @param maturity timestamp of option maturity
   */
  function exercise (
    uint amount,
    uint192 strikePrice,
    uint64 maturity
  ) external {
    exercise(_tokenIdFor(strikePrice, maturity), amount);
  }

  /**
   * @notice exercise put option
   * @param id ERC1155 token id
   * @param amount quantity of option contract tokens to exercise
   */
  function exercise (
    uint id,
    uint amount
  ) public {
    _burn(msg.sender, id, amount);

    // TODO: send payment
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
    return uint256(maturity) * (uint256(type(uint192).max) + 1) + strikePrice;
  }

  function _calculateC (
    int128 oldC,
    uint oldLiquidity,
    uint newLiquidity
  ) internal pure returns (int128) {
    int128 oldLiquidity64x64 = ABDKMath64x64.fromUInt(oldLiquidity);
    int128 newLiquidity64x64 = ABDKMath64x64.fromUInt(newLiquidity);

    return oldLiquidity64x64.sub(newLiquidity64x64).div(
      oldLiquidity64x64 > newLiquidity64x64 ? oldLiquidity64x64 : newLiquidity64x64
    ).neg().exp().mul(oldC);
  }
}
