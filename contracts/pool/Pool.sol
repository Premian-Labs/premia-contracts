// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';
import '@solidstate/contracts/token/ERC20/ERC20.sol';
import '@solidstate/contracts/token/ERC20/IERC20.sol';
import '@solidstate/contracts/token/ERC1155/ERC1155Base.sol';

import '../pair/IPair.sol';
import './PoolStorage.sol';

import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';
import { ABDKMath64x64Token } from '../libraries/ABDKMath64x64Token.sol';
import { OptionMath } from '../libraries/OptionMath.sol';

/**
 * @title Median option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is OwnableInternal, ERC20, ERC1155Base {
  using ABDKMath64x64 for int128;
  using ABDKMath64x64Token for int128;

  enum TokenType { OPTION, LIQUIDITY }

  address private immutable WETH_ADDRESS;

  constructor (
    address weth
  ) {
    WETH_ADDRESS = weth;
  }

  /**
   * @notice get address of PairProxy contract
   * @return pair address
   */
  function getPair () external view returns (address) {
    return PoolStorage.layout().pair;
  }

  /**
   * @notice calculate price of option contract
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @param amount size of option contract
   * @return price64x64 64x64 fixed point representation of option price
   */
  function quote (
    uint64 maturity,
    int128 strike64x64,
    uint256 amount
  ) public returns (int128 price64x64) {
    require(maturity > block.timestamp, 'Pool: maturity must be in the future');

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 amount64x64 = ABDKMath64x64Token.fromDecimals(amount, l.underlyingDecimals);

    int128 oldLiquidity64x64 = l.liquidity64x64;
    int128 newLiquidity64x64 = oldLiquidity64x64.add(amount64x64);

    (int128 spot64x64, int128 variance64x64) = IPair(l.pair).updateAndGetLatestData();
    int128 timeToMaturity64x64 = ABDKMath64x64.divu(maturity - block.timestamp, 365 days);

    price64x64 = OptionMath.quotePrice(
      variance64x64,
      strike64x64,
      spot64x64,
      timeToMaturity64x64,
      l.cLevel64x64,
      oldLiquidity64x64,
      newLiquidity64x64,
      OptionMath.ONE_64x64,
      false
    ).mul(amount64x64);
  }

  /**
   * @notice purchase put option
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @param amount size of option contract
   * @param maxCost maximum acceptable cost after accounting for slippage
   */
  function purchase (
    uint64 maturity,
    int128 strike64x64,
    uint256 amount,
    uint256 maxCost
  ) external payable returns (uint256 cost) {
    // TODO: maturity must be integer number of calendar days
    // TODO: specify payment currency
    // TODO: reserve liquidity
    // TODO: set C-Level
    // TODO: transfer portion of premium to treasury

    PoolStorage.Layout storage l = PoolStorage.layout();

    cost = quote(maturity, strike64x64, amount).toDecimals(l.baseDecimals);
    require(cost <= maxCost, 'Pool: excessive slippage');
    _pull(l.base, cost);

    _mint(msg.sender, _tokenIdFor(TokenType.OPTION, maturity, strike64x64), amount, '');
  }

  /**
   * @notice exercise put option
   * @param tokenId ERC1155 token id
   * @param amount quantity of option contract tokens to exercise
   */
  function exercise (
    uint256 tokenId,
    uint256 amount
  ) public {
    (TokenType tokenType, uint64 maturity, int128 strike64x64) = _parametersFor(tokenId);
    require(tokenType == TokenType.OPTION, 'Pool: invalid token type');

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 spot64x64 = IPair(l.pair).updateAndGetHistoricalPrice(
      maturity < block.timestamp ? maturity : block.timestamp
    );

    _burn(msg.sender, tokenId, amount);

    if (strike64x64 > spot64x64) {
      // option is in-the-money

      int128 value64x64 = strike64x64.sub(spot64x64).mul(ABDKMath64x64.fromUInt(amount));

      // TODO: convert base value to underlying value
      _push(l.underlying, value64x64.toDecimals(l.underlyingDecimals));
    }
  }

  /**
   * @notice deposit underlying currency, underwriting puts of that currency with respect to base currency
   * @param amount quantity of underlying currency to deposit
   * @return share of pool granted
   */
  function deposit (
    uint256 amount
  ) external payable returns (uint256 share) {
    PoolStorage.Layout storage l = PoolStorage.layout();

    // TODO: multiply by decimals

    _pull(l.underlying, amount);

    // TODO: mint liquidity tokens

    int128 oldLiquidity64x64 = l.liquidity64x64;
    int128 newLiquidity64x64 = oldLiquidity64x64.add(
      ABDKMath64x64Token.fromDecimals(amount, l.underlyingDecimals)
    );

    l.liquidity64x64 = newLiquidity64x64;

    l.cLevel64x64 = OptionMath.calculateCLevel(
      l.cLevel64x64,
      oldLiquidity64x64,
      newLiquidity64x64,
      OptionMath.ONE_64x64
    );
  }

  /**
   * @notice redeem pool share tokens for underlying asset
   * @param share quantity of share tokens to redeem
   * @return amount of underlying asset withdrawn
   */
  function withdraw (
    uint256 share
  ) external returns (uint256 amount) {
    // TODO: ensure available liquidity, queue if necessary

    PoolStorage.Layout storage l = PoolStorage.layout();

    // TODO: burn liquidity tokens

    // TODO: calculate share of pool

    // TODO: calculate amount out
    _push(l.underlying, amount);

    int128 oldLiquidity64x64 = l.liquidity64x64;
    int128 newLiquidity64x64 = oldLiquidity64x64.sub(
      ABDKMath64x64Token.fromDecimals(amount, l.underlyingDecimals)
    );

    l.liquidity64x64 = newLiquidity64x64;

    l.cLevel64x64 = OptionMath.calculateCLevel(
      l.cLevel64x64,
      oldLiquidity64x64,
      newLiquidity64x64,
      OptionMath.ONE_64x64
    );
  }

  /**
   * @notice calculate ERC1155 token id for given option parameters
   * @param tokenType TokenType enum
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @return tokenId token id
   */
  function _tokenIdFor (
    TokenType tokenType,
    uint64 maturity,
    int128 strike64x64
  ) internal pure returns (uint256 tokenId) {
    assembly {
      tokenId := add(strike64x64, add(shl(128, maturity), shl(248, tokenType)))
    }
  }

  /**
   * @notice derive option maturity and strike price from ERC1155 token id
   * @param tokenId token id
   * @return tokenType TokenType enum
   * @return maturity timestamp of option maturity
   * @return strike64x64 option strike price
   */
  function _parametersFor (
    uint256 tokenId
  ) internal pure returns (TokenType tokenType, uint64 maturity, int128 strike64x64) {
    assembly {
      tokenType := shr(248, tokenId)
      maturity := shr(128, tokenId)
      strike64x64 := tokenId
    }
  }

  /**
   * @notice transfer ERC20 tokens to message sender
   * @param token ERC20 token address
   * @param amount quantity of token to transfer
   */
  function _push (
    address token,
    uint256 amount
  ) internal {
    require(
      IERC20(token).transfer(msg.sender, amount),
      'Pool: ERC20 transfer failed'
    );
  }

  /**
   * @notice transfer ERC20 tokens from message sender
   * @param token ERC20 token address
   * @param amount quantity of token to transfer
   */
  function _pull (
    address token,
    uint256 amount
  ) internal {
    if (token == WETH_ADDRESS) {
      amount -= msg.value;
      // TODO: wrap ETH
    } else {
      require(msg.value == 0, 'Pool: function is payable only if deposit token is WETH');
    }

    if (amount > 0) {
      require(
        IERC20(token).transferFrom(msg.sender, address(this), amount),
        'Pool: ERC20 transfer failed'
      );
    }
  }
}
