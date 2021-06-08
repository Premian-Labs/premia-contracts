// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

import {OwnableInternal} from '@solidstate/contracts/access/OwnableInternal.sol';
import {IERC20} from '@solidstate/contracts/token/ERC20/IERC20.sol';
import {ERC1155Enumerable, EnumerableSet, ERC1155EnumerableStorage} from '@solidstate/contracts/token/ERC1155/ERC1155Enumerable.sol';
import {IWETH} from '@solidstate/contracts/utils/IWETH.sol';

import {PoolStorage} from './PoolStorage.sol';

import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';
import { ABDKMath64x64Token } from '../libraries/ABDKMath64x64Token.sol';
import { OptionMath } from '../libraries/OptionMath.sol';

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is OwnableInternal, ERC1155Enumerable {
  using ABDKMath64x64 for int128;
  using ABDKMath64x64Token for int128;
  using EnumerableSet for EnumerableSet.AddressSet;
  using PoolStorage for PoolStorage.Layout;

  address private immutable WETH_ADDRESS;
  address private immutable FEE_RECEIVER_ADDRESS;

  // TODO: make private
  uint internal immutable FREE_LIQUIDITY_TOKEN_ID;

  event Purchase (address indexed user,
                  address indexed base,
                  address indexed underlying,
                  int128 strike64x64,
                  uint64 maturity,
                  int128 cLevel64x64,
                  uint256 amount,
                  uint256 cost);
  event Exercise (address indexed user,
                  address indexed base,
                  address indexed underlying,
                  int128 spot64x64,
                  int128 strike64x64,
                  uint64 maturity,
                  uint256 amount,
                  int128 amountFreed64x64,
                  uint256 exerciseValue);
  event Deposit (address indexed user, address indexed base, address indexed underlying, uint256 amount);
  event Withdrawal (address indexed user, address indexed base, address indexed underlying, uint256 depositedAt, uint256 amount);
  event UpdateCLevel (address indexed base, address indexed underlying, int128 indexed cLevel64x64, int128 oldLiquidity64x64, int128 newLiquidity64x64);

  constructor (
    address weth,
    address feeReceiver
  ) {
    WETH_ADDRESS = weth;
    FEE_RECEIVER_ADDRESS = feeReceiver;
    FREE_LIQUIDITY_TOKEN_ID = PoolStorage.formatTokenId(PoolStorage.TokenType.FREE_LIQUIDITY, 0, 0);
  }

  /**
 * @notice get address of base token contract
 * @return base address
 */
  function getBase () external view returns (address) {
    return PoolStorage.layout().base;
  }

  /**
   * @notice get address of underlying token contract
   * @return underlying address
   */
  function getUnderlying () external view returns (address) {
    return PoolStorage.layout().underlying;
  }

  /**
   * @notice get address of base oracle contract
   * @return base oracle address
   */
  function getBaseOracle () external view returns (address) {
    return PoolStorage.layout().baseOracle;
  }

  /**
   * @notice get address of underlying oracle contract
   * @return underlying oracle address
   */
  function getUnderlyingOracle () external view returns (address) {
    return PoolStorage.layout().underlyingOracle;
  }

  /**
   * @notice get C Level
   * @return 64x64 fixed point representation of C-Level of Pool after purchase
   */
  function getCLevel64x64 () external view returns (int128) {
    return PoolStorage.layout().cLevel64x64;
  }

  /**
   * @notice get fees
   * @return 64x64 fixed point representation of fees
   */
  function getFee64x64 () external view returns (int128) {
    return PoolStorage.layout().fee64x64;
  }

  /**
   * @notice get ema log returns
   * @return 64x64 fixed point representation of natural log of rate of return for current period
   */
  function getEmaLogReturns64x64 () external view returns (int128) {
    return PoolStorage.layout().emaLogReturns64x64;
  }


  /**
   * @notice get ema variance annualized
   * @return 64x64 fixed point representation of ema variance annualized
   */
  function getEmaVarianceAnnualized64x64 () external view returns (int128) {
    return PoolStorage.layout().emaVarianceAnnualized64x64;
  }

  /**
   * @notice get price at timestamp
   * @return price at timestamp
   */
  function getPrice (uint256 timestamp) external view returns (int128) {
    return PoolStorage.layout().getPriceUpdate(timestamp);
  }


  /**
   * @notice calculate price of option contract
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @param spot64x64 64x64 fixed point representation of spot price
   * @param amount size of option contract
   * @return cost64x64 64x64 fixed point representation of option cost denominated in underlying currency
   * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
   */
  function quote (
    uint64 maturity,
    int128 strike64x64,
    int128 spot64x64,
    uint256 amount
  ) public view returns (int128 cost64x64, int128 cLevel64x64) {
    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 timeToMaturity64x64 = ABDKMath64x64.divu(maturity - block.timestamp, 365 days);

    int128 amount64x64 = ABDKMath64x64Token.fromDecimals(amount, l.underlyingDecimals);
    int128 oldLiquidity64x64 = l.totalSupply64x64(FREE_LIQUIDITY_TOKEN_ID);
    int128 newLiquidity64x64 = oldLiquidity64x64.sub(amount64x64);

    // TODO: validate values without spending gas
    // assert(oldLiquidity64x64 >= newLiquidity64x64);
    // assert(variance64x64 > 0);
    // assert(strike64x64 > 0);
    // assert(spot64x64 > 0);
    // assert(timeToMaturity64x64 > 0);

    int128 price64x64;

    (price64x64, cLevel64x64) = OptionMath.quotePrice(
      l.emaVarianceAnnualized64x64,
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

    require(amount <= totalSupply(FREE_LIQUIDITY_TOKEN_ID), 'Pool: insufficient liq');

    require(maturity >= block.timestamp + (1 days), 'Pool: maturity < 1 day');
    require(maturity < block.timestamp + (29 days), 'Pool: maturity > 28 days');
    require(maturity % (1 days) == 0, 'Pool: maturity not end UTC day');

    PoolStorage.Layout storage l = PoolStorage.layout();
    _update(l);

    int128 spot64x64 = l.getPriceUpdate(block.timestamp);

    require(strike64x64 <= spot64x64 << 1, 'Pool: strike > 2x spot');
    require(strike64x64 >= spot64x64 >> 1, 'Pool: strike < 0.5x spot');

    (int128 cost64x64, int128 cLevel64x64) = quote(
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
    emit Purchase(msg.sender, l.base, l.underlying, strike64x64, maturity, cLevel64x64, amount, cost);

    // mint free liquidity tokens for treasury
    _mint(FEE_RECEIVER_ADDRESS, FREE_LIQUIDITY_TOKEN_ID, fee, '');

    // mint long option token for buyer
    _mint(msg.sender, PoolStorage.formatTokenId(PoolStorage.TokenType.LONG_CALL, maturity, strike64x64), amount, '');

    uint256 shortTokenId = PoolStorage.formatTokenId(PoolStorage.TokenType.SHORT_CALL, maturity, strike64x64);

    _writeLoop(l, amount, cost - fee, shortTokenId);

    // update C-Level, accounting for slippage and reinvested premia separately

    int128 totalSupply64x64 = l.totalSupply64x64(FREE_LIQUIDITY_TOKEN_ID);

    l.setCLevel(OptionMath.calculateCLevel(
      cLevel64x64, // C-Level after liquidity is reserved
      totalSupply64x64.sub(cost64x64),
      totalSupply64x64,
      OptionMath.ONE_64x64
    ));

    emit UpdateCLevel(l.base, l.underlying, l.cLevel64x64, totalSupply64x64.sub(cost64x64), totalSupply64x64);
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
    uint64 maturity;
    int128 strike64x64;

    {
      PoolStorage.TokenType tokenType;
      (tokenType, maturity, strike64x64) = PoolStorage.parseTokenId(tokenId);
      require(tokenType == PoolStorage.TokenType.LONG_CALL, 'Pool: invalid token type');
    }

    PoolStorage.Layout storage l = PoolStorage.layout();
    _update(l);

    int128 spot64x64 = l.getPriceUpdateAfter(
      maturity < block.timestamp ? maturity : block.timestamp
    );

    // burn long option tokens from sender
    _burn(msg.sender, tokenId, amount);

    uint256 exerciseValue;
    uint256 amountRemaining = amount;

    if (spot64x64 > strike64x64) {
      // option has a non-zero exercise value
      exerciseValue = spot64x64.sub(strike64x64).div(spot64x64).mulu(amount);
      _push(l.underlying, exerciseValue);
      amountRemaining -= exerciseValue;
    }

    int128 oldLiquidity64x64 = l.totalSupply64x64(FREE_LIQUIDITY_TOKEN_ID);

    _exerciseLoop(
      l,
      amount,
      amountRemaining,
      exerciseValue,
      PoolStorage.formatTokenId(PoolStorage.TokenType.SHORT_CALL, maturity, strike64x64)
    );

    int128 newLiquidity64x64 = l.totalSupply64x64(FREE_LIQUIDITY_TOKEN_ID);

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64);

    emit Exercise(msg.sender, l.base, l.underlying, spot64x64, strike64x64, maturity, amount, newLiquidity64x64 - oldLiquidity64x64, exerciseValue);
    emit UpdateCLevel(l.base, l.underlying, l.cLevel64x64, oldLiquidity64x64, newLiquidity64x64);
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
    emit Deposit(msg.sender, l.base, l.underlying, amount);

    int128 oldLiquidity64x64 = l.totalSupply64x64(FREE_LIQUIDITY_TOKEN_ID);
    // mint free liquidity tokens for sender
    _mint(msg.sender, FREE_LIQUIDITY_TOKEN_ID, amount, '');
    int128 newLiquidity64x64 = l.totalSupply64x64(FREE_LIQUIDITY_TOKEN_ID);

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64);

    emit UpdateCLevel(l.base, l.underlying, l.cLevel64x64, oldLiquidity64x64, newLiquidity64x64);
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
      'Pool: liq must be locked 1 day'
    );

    int128 oldLiquidity64x64 = l.totalSupply64x64(FREE_LIQUIDITY_TOKEN_ID);
    // burn free liquidity tokens from sender
    _burn(msg.sender, FREE_LIQUIDITY_TOKEN_ID, amount);
    int128 newLiquidity64x64 = l.totalSupply64x64(FREE_LIQUIDITY_TOKEN_ID);

    _push(l.underlying, amount);
    emit Withdrawal(msg.sender, l.base, l.underlying, l.depositedAt[msg.sender], amount);

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64);

    emit UpdateCLevel(l.base, l.underlying, l.cLevel64x64, oldLiquidity64x64, newLiquidity64x64);
  }

  /**
   * @notice reassign short position to new liquidity provider
   * @param shortTokenId ERC1155 short token id
   * @param amount quantity of option contract tokens to reassign
   * @return cost quantity of tokens required to reassign short position
   */
  function reassign (
    uint256 shortTokenId,
    uint256 amount
  ) external returns (uint256 cost) {
    (PoolStorage.TokenType tokenType, uint64 maturity, int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);
    require(tokenType == PoolStorage.TokenType.SHORT_CALL, 'Pool: invalid token type');
    require(maturity > block.timestamp, 'Pool: option expired');

    // TODO: allow exit of expired position

    PoolStorage.Layout storage l = PoolStorage.layout();
    _update(l);

    int128 spot64x64 = l.getPriceUpdate(block.timestamp);

    (int128 cost64x64, int128 cLevel64x64) = quote(
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

    int128 totalSupply64x64 = l.totalSupply64x64(FREE_LIQUIDITY_TOKEN_ID);

    l.cLevel64x64 = OptionMath.calculateCLevel(
      cLevel64x64, // C-Level after liquidity is reserved
      totalSupply64x64,
      totalSupply64x64.add(cost64x64),
      OptionMath.ONE_64x64
    );

    emit UpdateCLevel(l.base, l.underlying, l.cLevel64x64, totalSupply64x64, totalSupply64x64.add(cost64x64));

    // mint free liquidity tokens for treasury
    _mint(FEE_RECEIVER_ADDRESS, FREE_LIQUIDITY_TOKEN_ID, fee, '');

    // burn short option tokens from underwriter
    _burn(msg.sender, shortTokenId, amount);

    _writeLoop(l, amount, cost - fee, shortTokenId);
  }

  /**
   * @notice Update pool data
   */
  function update () public {
    _update(PoolStorage.layout());
  }

  function _writeLoop (
    PoolStorage.Layout storage l,
    uint256 amount,
    uint256 premium,
    uint256 shortTokenId
  ) private {
    address underwriter;

    while (amount > 0) {
      underwriter = l.liquidityQueueAscending[underwriter];

      // amount of liquidity provided by underwriter, accounting for reinvested premium
      uint256 intervalAmount = balanceOf(underwriter, FREE_LIQUIDITY_TOKEN_ID) * (amount + premium) / amount;
      if (amount < intervalAmount) intervalAmount = amount;

      // amount of premium paid to underwriter
      uint256 intervalPremium = premium * intervalAmount / amount;
      premium -= intervalPremium;
      amount -= intervalAmount;

      // burn free liquidity tokens from underwriter
      _burn(underwriter, FREE_LIQUIDITY_TOKEN_ID, intervalAmount - intervalPremium);
      // mint short option tokens for underwriter
      _mint(underwriter, shortTokenId, intervalAmount, '');
    }
  }

  function _exerciseLoop (
    PoolStorage.Layout storage l,
    uint256 amount,
    uint256 amountRemaining,
    uint256 exerciseValue,
    uint256 shortTokenId
  ) private {
    EnumerableSet.AddressSet storage underwriters = ERC1155EnumerableStorage.layout().accountsByToken[shortTokenId];

    while (amount > 0) {
      address underwriter = underwriters.at(underwriters.length() - 1);

      // amount of liquidity provided by underwriter
      uint256 intervalAmount = balanceOf(underwriter, shortTokenId);
      if (amountRemaining < intervalAmount) intervalAmount = amountRemaining;

      // amount of liquidity returned to underwriter, accounting for premium earned by buyer
      uint256 freedAmount = intervalAmount * (amount - exerciseValue) / amount;
      amountRemaining -= freedAmount;

      // mint free liquidity tokens for underwriter
      _mint(underwriter, FREE_LIQUIDITY_TOKEN_ID, freedAmount, '');
      // burn short option tokens from underwriter
      _burn(underwriter, shortTokenId, intervalAmount);
    }
  }

  /**
   * @notice TODO
   */
  function _update (
    PoolStorage.Layout storage l
  ) internal {
    uint256 updatedAt = l.updatedAt;

    int128 oldPrice64x64 = l.getPriceUpdate(updatedAt);
    int128 newPrice64x64 = l.fetchPriceUpdate();

    if (l.getPriceUpdate(block.timestamp) == 0) {
      l.setPriceUpdate(block.timestamp, newPrice64x64);
    }

    int128 logReturns64x64 = newPrice64x64.div(oldPrice64x64).ln();
    int128 oldEmaLogReturns64x64 = l.emaLogReturns64x64;

    l.emaLogReturns64x64 = OptionMath.unevenRollingEma(
      oldEmaLogReturns64x64,
      logReturns64x64,
      updatedAt,
      block.timestamp
    );

    l.emaVarianceAnnualized64x64 = OptionMath.unevenRollingEmaVariance(
      oldEmaLogReturns64x64,
      l.emaVarianceAnnualized64x64 / 365,
      logReturns64x64,
      updatedAt,
      block.timestamp
    ) * 365;

    l.updatedAt = block.timestamp;
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
      if (msg.value > 0) {
        require(msg.value <= amount, "Pool: too much ETH sent");

        unchecked {
          amount -= msg.value;
        }

        IWETH(WETH_ADDRESS).deposit{ value: msg.value }();
      }
    } else {
      require(
        msg.value == 0,
        'Pool: not WETH deposit'
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
   * @notice ERC1155 hook: track eligible underwriters
   * @param operator transaction sender
   * @param from token sender
   * @param to token receiver
   * @param ids token ids transferred
   * @param amounts token quantities transferred
   * @param data data payload
   */
  function _beforeTokenTransfer (
    address operator,
    address from,
    address to,
    uint[] memory ids,
    uint[] memory amounts,
    bytes memory data
  ) override internal {
    super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

    // TODO: use linked list for ERC1155Enumerable
    // TODO: enforce minimum balance

    for (uint i; i < ids.length; i++) {
      if (ids[i] == FREE_LIQUIDITY_TOKEN_ID) {
        if (amounts[i] > 0) {
          PoolStorage.Layout storage l = PoolStorage.layout();

          if (from != address(0) && balanceOf(from, FREE_LIQUIDITY_TOKEN_ID) == amounts[i]) {
            l.removeUnderwriter(from);
          }

          if (to != address(0) && balanceOf(to, FREE_LIQUIDITY_TOKEN_ID) == 0) {
            l.addUnderwriter(to);
          }
        }
      }
    }
  }
}
