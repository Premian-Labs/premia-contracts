// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';
import '@solidstate/contracts/token/ERC20/IERC20.sol';
import '@solidstate/contracts/token/ERC1155/ERC1155Base.sol';

import '../pair/Pair.sol';
import './PoolStorage.sol';

import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';
import { OptionMath } from "../libraries/OptionMath.sol";

/**
 * @title Median option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is OwnableInternal, ERC1155Base {
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
   * @param maturity timestamp of option maturity
   * @param strikePrice option strike price
   * @return price price of option contract
   * @return cLevel C-Level after purchase
   */
  function quote (
    uint amount,
    uint64 maturity,
    int128 strikePrice
  ) public view returns (uint price, int128 cLevel) {
    require(maturity > block.timestamp, 'Pool: expiration must be in the future');
    // TODO: calculate

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 volatility = Pair(l.pair).getVolatility();

    uint liquidity = l.liquidity;

    // TODO: store liquidity as int128?
    cLevel = OptionMath.calculateCLevel(
      l.cLevel,
      ABDKMath64x64.fromUInt(liquidity),
      ABDKMath64x64.fromUInt(liquidity - amount),
      OptionMath.ONE_64x64
    );
  }

  /**
   * @notice TODO
   */
  function valueOfOption (
    uint tokenId,
    uint amount
  ) public view returns (int128) {
    (uint8 tokenType, uint64 maturity, int128 strikePrice) = _parametersFor(tokenId);
    // TODO: verify tokenType

    // TODO: get spot price now or at maturity
    int128 spotPrice;

    if (strikePrice > spotPrice) {
      return strikePrice.sub(spotPrice).mul(ABDKMath64x64.fromUInt(amount));
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

    // TODO: mint liquidity tokens

    uint oldLiquidity = l.liquidity;
    uint newLiquidity = oldLiquidity + amount;

    l.cLevel = OptionMath.calculateCLevel(
      l.cLevel,
      ABDKMath64x64.fromUInt(oldLiquidity),
      ABDKMath64x64.fromUInt(newLiquidity),
      OptionMath.ONE_64x64
    );

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

    // TODO: burn liquidity tokens

    // TODO: calculate share of pool

    IERC20(l.underlying).transfer(msg.sender, amount);

    uint oldLiquidity = l.liquidity;
    uint newLiquidity = oldLiquidity - amount;

    l.cLevel = OptionMath.calculateCLevel(
      l.cLevel,
      ABDKMath64x64.fromUInt(oldLiquidity),
      ABDKMath64x64.fromUInt(newLiquidity),
      OptionMath.ONE_64x64
    );

    l.liquidity = newLiquidity;
  }

  /**
   * @notice purchase put option
   * @param amount size of option contract
   * @param maturity timestamp of option maturity
   * @param strikePrice option strike price
   */
  function purchase (
    uint amount,
    uint64 maturity,
    int128 strikePrice
  ) external returns (uint price) {
    // TODO: convert ETH to WETH if applicable
    // TODO: maturity must be integer number of calendar days
    // TODO: accept minimum price to prevent slippage
    // TODO: reserve liquidity

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 cLevel;
    (price, cLevel) = quote(amount, maturity, strikePrice);
    l.cLevel = cLevel;

    IERC20(l.base).transferFrom(msg.sender, address(this), price);

    // TODO: tokenType
    _mint(msg.sender, _tokenIdFor(0, maturity, strikePrice), amount, '');
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
    // TODO: multiply by decimals
    uint value = valueOfOption(tokenId, amount).toUInt();

    require(value > 0, 'Pool: option must be in-the-money');

    _burn(msg.sender, tokenId, amount);

    IERC20(PoolStorage.layout().underlying).transfer(msg.sender, value);
  }

  /**
   * @notice calculate ERC1155 token id for given option parameters
   * @param tokenType TODO
   * @param maturity timestamp of option maturity
   * @param strikePrice option strike price
   * @return tokenId token id
   */
  function _tokenIdFor (
    uint8 tokenType,
    uint64 maturity,
    int128 strikePrice
  ) internal pure returns (uint tokenId) {
    assembly {
      tokenId := add(strikePrice, add(shl(128, maturity), shl(248, tokenType)))
    }
  }

  /**
   * @notice derive option maturity and strike price from ERC1155 token id
   * @param tokenId token id
   * @return tokenType TODO
   * @return maturity timestamp of option maturity
   * @return strikePrice option strike price
   */
  function _parametersFor (
    uint tokenId
  ) internal pure returns (uint8 tokenType, uint64 maturity, int128 strikePrice) {
    assembly {
      tokenType := shr(248, tokenId)
      maturity := shr(128, tokenId)
      strikePrice := tokenId
    }
  }
}
