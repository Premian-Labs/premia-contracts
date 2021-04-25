// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';
import '@solidstate/contracts/token/ERC20/ERC20.sol';
import '@solidstate/contracts/token/ERC20/IERC20.sol';
import '@solidstate/contracts/token/ERC1155/ERC1155Enumerable.sol';

import '../pair/IPair.sol';
import './PoolStorage.sol';

import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';
import { ABDKMath64x64Token } from '../libraries/ABDKMath64x64Token.sol';
import { OptionMath } from '../libraries/OptionMath.sol';

/**
 * @title Median option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is OwnableInternal, ERC20, ERC1155Enumerable {
  using ABDKMath64x64 for int128;
  using ABDKMath64x64Token for int128;
  using PoolStorage for PoolStorage.Layout;

  enum TokenType { LONG_PUT, SHORT_PUT }

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
   * @notice calculate price of option contract and trigger Pair state update
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @param amount size of option contract
   * @return cost64x64 64x64 fixed point representation of option cost
   * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
   */
  function quote (
    uint64 maturity,
    int128 strike64x64,
    uint256 amount
  ) public returns (int128 cost64x64, int128 cLevel64x64) {
    require(maturity >= block.timestamp + (1 days), 'Pool: maturity must be at least 1 day in the future');
    require(maturity < block.timestamp + (29 days), 'Pool: maturity must be at most 28 days in the future');
    require(maturity % (1 days) == 0, 'Pool: maturity must correspond to end of UTC day');

    PoolStorage.Layout storage l = PoolStorage.layout();

    (int128 spot64x64, int128 variance64x64) = IPair(l.pair).updateAndGetLatestData();

    require(strike64x64 <= spot64x64 * 2, 'Pool: strike price must not exceed two times spot price');
    require(strike64x64 >= spot64x64 / 2, 'Pool: strike price must be at least one half spot price');

    int128 timeToMaturity64x64 = ABDKMath64x64.divu(maturity - block.timestamp, 365 days);

    int128 amount64x64 = ABDKMath64x64Token.fromDecimals(amount, l.underlyingDecimals);
    int128 oldLiquidity64x64 = l.totalSupply64x64();
    int128 newLiquidity64x64 = oldLiquidity64x64.sub(amount64x64);

    // TODO: validate values without spending gas
    // assert(oldLiquidity64x64 >= newLiquidity64x64);
    // assert(variance64x64 > 0);
    // assert(strike64x64 > 0);
    // assert(spot64x64 > 0);
    // assert(timeToMaturity64x64 > 0);

    int128 price64x64;

    (price64x64, cLevel64x64) = OptionMath.quotePrice(
      variance64x64,
      strike64x64,
      spot64x64,
      timeToMaturity64x64,
      l.cLevel64x64,
      oldLiquidity64x64,
      newLiquidity64x64,
      OptionMath.ONE_64x64,
      false
    );

    cost64x64 = price64x64.mul(amount64x64);
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
    // TODO: specify payment currency
    // TODO: transfer portion of premium to treasury

    require(amount <= totalSupply(), 'Pool: insufficient liquidity');

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 cost64x64;
    (cost64x64, l.cLevel64x64) = quote(maturity, strike64x64, amount);
    cost = cost64x64.toDecimals(l.baseDecimals);
    require(cost <= maxCost, 'Pool: excessive slippage');
    _pull(l.base, cost);

    // mint long option token (ERC1155)
    _mint(msg.sender, _tokenIdFor(TokenType.LONG_PUT, maturity, strike64x64), amount, '');

    uint256 shortTokenId = _tokenIdFor(TokenType.SHORT_PUT, maturity, strike64x64);
    address underwriter;

    while (amount > 0) {
      underwriter = l.liquidityQueueAscending[underwriter];
      uint256 balance = balanceOf(underwriter);

      uint256 intervalAmount = balance < amount ? balance : amount;
      amount -= intervalAmount;

      // burn free liquidity tokens (ERC20)
      _burn(underwriter, intervalAmount);
      // mint short option token (ERC1155)
      _mint(underwriter, shortTokenId, intervalAmount, '');

      // TODO: transfer premia

      if (intervalAmount == balance) {
        l.removeUnderwriter(underwriter);
      }
    }
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
    require(tokenType == TokenType.LONG_PUT, 'Pool: invalid token type');

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 spot64x64 = IPair(l.pair).updateAndGetHistoricalPrice(
      maturity < block.timestamp ? maturity : block.timestamp
    );

    // burn long option token (ERC1155)
    _burn(msg.sender, tokenId, amount);

    if (strike64x64 > spot64x64) {
      // option is in-the-money
      uint value = strike64x64.sub(spot64x64).mulu(amount);
      _push(l.underlying, value);
      amount -= value;
    }

    int128 oldLiquidity64x64 = l.totalSupply64x64();

    uint256 shortTokenId = _tokenIdFor(TokenType.SHORT_PUT, maturity, strike64x64);
    address underwriter;

    while (amount > 0) {
      // TODO: iterate through short option token holders via ERC1155Enumerable
      underwriter = underwriter;
      uint256 balance = balanceOf(underwriter);

      if (balance == 0) {
        l.addUnderwriter(underwriter);
      }

      // TODO: quantity of short tokens corresponding to freed liquidity
      uint256 fullAmount;

      // TODO: amount of freed liquidity
      uint256 intervalAmount;
      amount -= intervalAmount;

      // mint free liquidity tokens (ERC20)
      _mint(underwriter, intervalAmount);
      // burn short option token (ERC1155)
      _burn(underwriter, shortTokenId, fullAmount);
    }

    int128 newLiquidity64x64 = l.totalSupply64x64();

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64);
  }

  /**
   * @notice deposit underlying currency, underwriting puts of that currency with respect to base currency
   * @param amount quantity of underlying currency to deposit
   */
  function deposit (
    uint256 amount
  ) external payable {
    PoolStorage.Layout storage l = PoolStorage.layout();

    _pull(l.underlying, amount);

    if (balanceOf(msg.sender) == 0) {
      require(amount > 0, 'TODO');
      l.addUnderwriter(msg.sender);
    }

    int128 oldLiquidity64x64 = l.totalSupply64x64();
    // mint free liquidity tokens (ERC20)
    _mint(msg.sender, amount);
    int128 newLiquidity64x64 = l.totalSupply64x64();

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64);
  }

  /**
   * @notice redeem pool share tokens for underlying asset
   * @param amount quantity of share tokens to redeem
   */
  function withdraw (
    uint256 amount
  ) external {
    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 oldLiquidity64x64 = l.totalSupply64x64();
    // burn free liquidity tokens (ERC20)
    _burn(msg.sender, amount);
    int128 newLiquidity64x64 = l.totalSupply64x64();

    if (balanceOf(msg.sender) == 0) {
      l.removeUnderwriter(msg.sender);
    }

    // TODO: reassign held options if necessary

    _push(l.underlying, amount);

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64);
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
      require(
        msg.value == 0,
        'Pool: function is payable only if deposit token is WETH'
      );
    }

    if (amount > 0) {
      require(
        IERC20(token).transferFrom(msg.sender, address(this), amount),
        'Pool: ERC20 transfer failed'
      );
    }
  }
}
