// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';
import '@solidstate/contracts/token/ERC20/ERC20.sol';
import '@solidstate/contracts/token/ERC20/IERC20.sol';
import '@solidstate/contracts/token/ERC1155/ERC1155Enumerable.sol';
import '@solidstate/contracts/utils/IWETH.sol';

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
  using EnumerableSet for EnumerableSet.AddressSet;
  using PoolStorage for PoolStorage.Layout;

  enum TokenType { LONG_CALL, SHORT_CALL }

  address private immutable WETH_ADDRESS;

  event Purchase (address account, uint256 amount);
  event Exercise (address account, uint256 amount);
  event Deposit (address account, uint256 amount);
  event Withdrawal (address account, uint256 amount);
  event UpdateCLevel (int128 cLevel64x64);
  event CreatePool (address indexed base, address indexed underlying, address indexed treasury, int128 initialCLevel);

  constructor (
    address weth
  ) {
    WETH_ADDRESS = weth;
    PoolStorage.Layout storage l = PoolStorage.layout();

    emit CreatePool(l.base, l.underlying, l.treasury, l.cLevel64x64);
  }

  /**
   * @notice get address of PairProxy contract
   * @return pair address
   */
  function getPair () external view returns (address) {
    return PoolStorage.layout().pair;
  }

  /**
   * @notice get address of underlying token contract
   * @return underlying address
   */
  function getUnderlying () external view returns (address) {
    return PoolStorage.layout().underlying;
  }

  /**
   * @notice calculate price of option contract
   * @param variance64x64 64x64 fixed point representation of variance
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @param spot64x64 64x64 fixed point representation of spot price
   * @param amount size of option contract
   * @return cost64x64 64x64 fixed point representation of option cost denominated in underlying currency
   * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
   */
  function quote (
    int128 variance64x64,
    uint64 maturity,
    int128 strike64x64,
    int128 spot64x64,
    uint256 amount
  ) public view returns (int128 cost64x64, int128 cLevel64x64) {
    PoolStorage.Layout storage l = PoolStorage.layout();

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
      true
    );

    cost64x64 = price64x64.mul(amount64x64).mul(
      OptionMath.ONE_64x64.add(l.fee64x64)
    ).mul(spot64x64);
  }

  /**
   * @notice purchase call option
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @param amount size of option contract
   * @param maxCost maximum acceptable cost after accounting for slippage
   * @return cost quantity of tokens required to purchase long position
   */
  function purchase (
    uint64 maturity,
    int128 strike64x64,
    uint256 amount,
    uint256 maxCost
  ) external payable returns (uint256 cost) {
    // TODO: specify payment currency

    require(amount <= totalSupply(), 'Pool: insufficient liquidity');

    require(maturity >= block.timestamp + (1 days), 'Pool: maturity must be at least 1 day in the future');
    require(maturity < block.timestamp + (29 days), 'Pool: maturity must be at most 28 days in the future');
    require(maturity % (1 days) == 0, 'Pool: maturity must correspond to end of UTC day');

    PoolStorage.Layout storage l = PoolStorage.layout();

    (int128 spot64x64, int128 variance64x64) = IPair(l.pair).updateAndGetLatestData();

    require(strike64x64 <= spot64x64 << 1, 'Pool: strike price must not exceed two times spot price');
    require(strike64x64 >= spot64x64 >> 1, 'Pool: strike price must be at least one half spot price');

    (int128 cost64x64, int128 cLevel64x64) = quote(
      variance64x64,
      maturity,
      strike64x64,
      spot64x64,
      amount
    );

    cost = cost64x64.toDecimals(l.underlyingDecimals);
    uint256 fee = cost64x64.mul(l.fee64x64).div(
      OptionMath.ONE_64x64.add(l.fee64x64)
    ).toDecimals(l.underlyingDecimals);

    require(cost <= maxCost, 'Pool: excessive slippage');
    _pull(l.underlying, cost);
    emit Purchase(msg.sender, cost);

    // mint free liquidity tokens for treasury (ERC20)
    _mint(l.treasury, fee);

    // mint long option token for buyer (ERC1155)
    _mint(msg.sender, _tokenIdFor(TokenType.LONG_CALL, maturity, strike64x64), amount, '');

    // remaining premia to be distributed to underwriters
    uint256 costRemaining = cost - fee;

    uint256 shortTokenId = _tokenIdFor(TokenType.SHORT_CALL, maturity, strike64x64);
    address underwriter;

    while (amount > 0) {
      underwriter = l.liquidityQueueAscending[underwriter];

      // amount of liquidity provided by underwriter, accounting for reinvested premium
      uint256 intervalAmount = balanceOf(underwriter) * (amount + costRemaining) / amount;
      if (amount < intervalAmount) intervalAmount = amount;
      amount -= intervalAmount;

      // amount of premium paid to underwriter
      uint256 intervalCost = costRemaining * intervalAmount / amount;
      costRemaining -= intervalCost;

      // burn free liquidity tokens from underwriter (ERC20)
      _burn(underwriter, intervalAmount - intervalCost);
      // mint short option token for underwriter (ERC1155)
      _mint(underwriter, shortTokenId, intervalAmount, '');
    }

    // update C-Level, accounting for slippage and reinvested premia separately

    int128 totalSupply64x64 = l.totalSupply64x64();

    l.setCLevel(OptionMath.calculateCLevel(
      cLevel64x64, // C-Level after liquidity is reserved
      totalSupply64x64.sub(cost64x64),
      totalSupply64x64,
      OptionMath.ONE_64x64
    ));

    emit UpdateCLevel(l.cLevel64x64);
  }

  /**
   * @notice exercise call option
   * @param tokenId ERC1155 token id
   * @param amount quantity of option contract tokens to exercise
   */
  function exercise (
    uint256 tokenId,
    uint256 amount
  ) public {
    (TokenType tokenType, uint64 maturity, int128 strike64x64) = _parametersFor(tokenId);
    require(tokenType == TokenType.LONG_CALL, 'Pool: invalid token type');

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 spot64x64 = IPair(l.pair).updateAndGetHistoricalPrice(
      maturity < block.timestamp ? maturity : block.timestamp
    );

    // burn long option tokens from sender (ERC1155)
    _burn(msg.sender, tokenId, amount);

    uint256 exerciseValue;
    uint256 amountRemaining = amount;

    if (spot64x64 > strike64x64) {
      // option has a non-zero exercise value
      exerciseValue = spot64x64.sub(strike64x64).div(spot64x64).mulu(amount);
      _push(l.underlying, exerciseValue);
      emit Exercise(msg.sender, exerciseValue);
      amountRemaining -= exerciseValue;
    }

    int128 oldLiquidity64x64 = l.totalSupply64x64();

    uint256 shortTokenId = _tokenIdFor(TokenType.SHORT_CALL, maturity, strike64x64);
    EnumerableSet.AddressSet storage underwriters = ERC1155EnumerableStorage.layout().accountsByToken[shortTokenId];

    while (amount > 0) {
      address underwriter = underwriters.at(underwriters.length() - 1);

      // amount of liquidity provided by underwriter
      uint256 intervalAmount = balanceOf(underwriter, shortTokenId);
      if (amountRemaining < intervalAmount) intervalAmount = amountRemaining;

      // amount of liquidity returned to underwriter, accounting for premium earned by buyer
      uint256 freedAmount = intervalAmount * (amount - exerciseValue) / amount;
      amountRemaining -= freedAmount;

      // mint free liquidity tokens for underwriter (ERC20)
      _mint(underwriter, freedAmount);
      // burn short option tokens from underwriter (ERC1155)
      _burn(underwriter, shortTokenId, intervalAmount);
    }

    int128 newLiquidity64x64 = l.totalSupply64x64();

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64);

    emit UpdateCLevel(l.cLevel64x64);
  }

  /**
   * @notice deposit underlying currency, underwriting calls of that currency with respect to base currency
   * @param amount quantity of underlying currency to deposit
   */
  function deposit (
    uint256 amount
  ) external payable {
    PoolStorage.Layout storage l = PoolStorage.layout();

    l.depositedAt[msg.sender] = block.timestamp;

    _pull(l.underlying, amount);
    emit Deposit(msg.sender, amount);

    int128 oldLiquidity64x64 = l.totalSupply64x64();
    // mint free liquidity tokens for sender (ERC20)
    _mint(msg.sender, amount);
    int128 newLiquidity64x64 = l.totalSupply64x64();

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64);

    emit UpdateCLevel(l.cLevel64x64);
  }

  /**
   * @notice redeem pool share tokens for underlying asset
   * @param amount quantity of share tokens to redeem
   */
  function withdraw (
    uint256 amount
  ) external {
    PoolStorage.Layout storage l = PoolStorage.layout();

    require(
      l.depositedAt[msg.sender] + (1 days) < block.timestamp,
      'Pool: liquidity must remain locked for 1 day'
    );

    int128 oldLiquidity64x64 = l.totalSupply64x64();
    // burn free liquidity tokens from sender (ERC20)
    _burn(msg.sender, amount);
    int128 newLiquidity64x64 = l.totalSupply64x64();

    _push(l.underlying, amount);
    emit Withdrawal(msg.sender, amount);

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64);

    emit UpdateCLevel(l.cLevel64x64);
  }

  /**
   * @notice reassign short position to new liquidity provider
   * @param tokenId ERC1155 token id
   * @param amount quantity of option contract tokens to reassign
   * @return cost quantity of tokens required to reassign short position
   */
  function reassign (
    uint256 tokenId,
    uint256 amount
  ) external returns (uint256 cost) {
    (TokenType tokenType, uint64 maturity, int128 strike64x64) = _parametersFor(tokenId);
    require(tokenType == TokenType.SHORT_CALL, 'Pool: invalid token type');
    require(maturity > block.timestamp, 'Pool: option must not be expired');

    // TODO: allow exit of expired position

    PoolStorage.Layout storage l = PoolStorage.layout();

    uint256 costRemaining;

    {
      (int128 spot64x64, int128 variance64x64) = IPair(l.pair).updateAndGetLatestData();
      (int128 cost64x64, int128 cLevel64x64) = quote(
        variance64x64,
        maturity,
        strike64x64,
        spot64x64,
        amount
      );

      cost = cost64x64.toDecimals(l.underlyingDecimals);
      uint256 fee = cost64x64.mul(l.fee64x64).div(
        OptionMath.ONE_64x64.add(l.fee64x64)
      ).toDecimals(l.underlyingDecimals);

      _push(l.underlying, amount - cost - fee);
      // TODO: reassignment event

      // update C-Level, accounting for slippage and reinvested premia separately

      int128 totalSupply64x64 = l.totalSupply64x64();

      l.setCLevel(OptionMath.calculateCLevel(
        cLevel64x64, // C-Level after liquidity is reserved
        totalSupply64x64,
        totalSupply64x64.add(cost64x64),
        OptionMath.ONE_64x64
      ));

      emit UpdateCLevel(l.cLevel64x64);

      // mint free liquidity tokens for treasury (ERC20)
      _mint(l.treasury, fee);

      // remaining premia to be distributed to underwriters
      costRemaining = cost - fee;
    }

    address underwriter;

    while (amount > 0) {
      underwriter = l.liquidityQueueAscending[underwriter];

      // amount of liquidity provided by underwriter, accounting for reinvested premium
      uint256 intervalAmount = balanceOf(underwriter) * (amount + costRemaining) / amount;
      if (amount < intervalAmount) intervalAmount = amount;
      amount -= intervalAmount;

      // amount of premium paid to underwriter
      uint256 intervalCost = costRemaining * intervalAmount / amount;
      costRemaining -= intervalCost;

      // burn free liquidity tokens from underwriter (ERC20)
      _burn(underwriter, intervalAmount - intervalCost);
      // transfer short option token (ERC1155)
      _transfer(msg.sender, msg.sender, underwriter, tokenId, intervalAmount, '');
    }
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
      IWETH(WETH_ADDRESS).deposit{ value: msg.value }();
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

  /**
   * @notice ERC20 hook: track eligible underwriters
   * @param from token sender
   * @param to token receiver
   * @param amount token quantity transferred
   */
  function _beforeTokenTransfer (
    address from,
    address to,
    uint256 amount
  ) override internal {
    super._beforeTokenTransfer(from, to, amount);

    // TODO: enforce minimum balance

    if (amount > 0) {
      PoolStorage.Layout storage l = PoolStorage.layout();

      if (from != address(0) && balanceOf(from) == amount) {
        l.removeUnderwriter(from);
      }

      if (to != address(0) && balanceOf(to) == 0) {
        l.addUnderwriter(to);
      }
    }
  }
}
