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
  uint256 internal immutable UNDERLYING_FREE_LIQ_TOKEN_ID;
  uint256 internal immutable BASE_FREE_LIQ_TOKEN_ID;

  event Purchase (
    address indexed user,
    address indexed base,
    address indexed underlying,
    bool isCall,
    int128 strike64x64,
    uint64 maturity,
    int128 cLevel64x64,
    uint256 amount,
    uint256 baseCost,
    uint256 feeCost
  );

  event Exercise (
    address indexed user,
    address indexed base,
    address indexed underlying,
    bool isCall,
    int128 spot64x64,
    int128 strike64x64,
    uint64 maturity,
    uint256 amount,
    int128 amountFreed64x64,
    uint256 exerciseValue
  );

  event Underwrite (
    address indexed underwriter,
    address indexed base,
    address indexed underlying,
    bool isCall,
    uint256 shortTokenId,
    uint256 intervalAmount,
    uint256 intervalPremium
  );

  event AssignExercise (
    address indexed underwriter,
    address indexed base,
    address indexed underlying,
    bool isCall,
    uint256 shortTokenId,
    uint256 freedAmount,
    uint256 intervalAmount
  );

  event Reassign (
    address indexed underwriter,
    address indexed base,
    address indexed underlying,
    bool isCall,
    uint256 shortTokenId,
    uint256 amount,
    uint256 baseCost,
    uint256 feeCost,
    int128 cLevel64x64,
    int128 spot64x64
  );

  event Deposit (
    address indexed user,
    address indexed base,
    address indexed underlying,
    bool isCallPool,
    uint256 amount
  );

  event Withdrawal (
    address indexed user,
    address indexed base,
    address indexed underlying,
    bool isCallPool,
    uint256 depositedAt,
    uint256 amount
  );

  event UpdateCLevel (
    address indexed base,
    address indexed underlying,
    bool indexed isCall,
    int128 cLevel64x64,
    int128 oldLiquidity64x64,
    int128 newLiquidity64x64
  );

  constructor (
    address weth,
    address feeReceiver
  ) {
    WETH_ADDRESS = weth;
    FEE_RECEIVER_ADDRESS = feeReceiver;
    UNDERLYING_FREE_LIQ_TOKEN_ID = PoolStorage.formatTokenId(PoolStorage.TokenType.UNDERLYING_FREE_LIQ, 0, 0);
    BASE_FREE_LIQ_TOKEN_ID = PoolStorage.formatTokenId(PoolStorage.TokenType.BASE_FREE_LIQ, 0, 0);
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
  function getCLevel64x64 (bool isCall) external view returns (int128) {
    return PoolStorage.layout().getCLevel(isCall);
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
   * @param args arguments of the quote
   * @return baseCost64x64 64x64 fixed point representation of option cost denominated in underlying currency (without fee)
   * @return feeCost64x64 64x64 fixed point representation of option fee cost denominated in underlying currency for call, or base currency for put
   * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
   */
  function quote (
    PoolStorage.QuoteArgs memory args
  ) public view returns (int128 baseCost64x64, int128 feeCost64x64, int128 cLevel64x64) {
    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 amount64x64 = ABDKMath64x64Token.fromDecimals(args.amount, l.underlyingDecimals);

    int128 oldLiquidity64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(args.isCall));

    require(oldLiquidity64x64 > 0, "Pool: No liq");

    // TODO: validate values without spending gas
    // assert(oldLiquidity64x64 >= newLiquidity64x64);
    // assert(variance64x64 > 0);
    // assert(strike64x64 > 0);
    // assert(spot64x64 > 0);
    // assert(timeToMaturity64x64 > 0);

    int128 price64x64;

    // Keep as is, to avoid stack too deep error
    if (args.isCall) {
      (price64x64, cLevel64x64) = OptionMath.quotePrice(
        l.emaVarianceAnnualized64x64,
        args.strike64x64,
        args.spot64x64,
        ABDKMath64x64.divu(args.maturity - block.timestamp, 365 days),
        l.cLevelUnderlying64x64,
        oldLiquidity64x64,
        oldLiquidity64x64.sub(amount64x64),
        OptionMath.ONE_64x64,
        true
      );
    } else {
      (price64x64, cLevel64x64) = OptionMath.quotePrice(
        l.emaVarianceAnnualized64x64,
        args.strike64x64,
        args.spot64x64,
        ABDKMath64x64.divu(args.maturity - block.timestamp, 365 days),
        l.cLevelBase64x64,
        oldLiquidity64x64,
        oldLiquidity64x64.sub(amount64x64),
        OptionMath.ONE_64x64,
        false
      );
    }


    baseCost64x64 = price64x64.mul(amount64x64);

    if (args.isCall) {
      baseCost64x64 = baseCost64x64.div(args.spot64x64);
    }

    feeCost64x64 = baseCost64x64.mul(l.fee64x64);
  }

  /**
   * @notice purchase call option
   * @param args arguments for purchase
   * @return baseCost quantity of tokens required to purchase long position
   * @return feeCost quantity of tokens required to pay fees
   */
  function purchase (
    PoolStorage.PurchaseArgs memory args
  ) external payable returns (uint256 baseCost, uint256 feeCost) {
    // TODO: specify payment currency

    require(args.amount <= totalSupply(_getFreeLiquidityTokenId(args.isCall)), 'Pool: insufficient liq');

    require(args.maturity >= block.timestamp + (1 days), 'Pool: maturity < 1 day');
    require(args.maturity < block.timestamp + (29 days), 'Pool: maturity > 28 days');
    require(args.maturity % (1 days) == 0, 'Pool: maturity not end UTC day');

    PoolStorage.Layout storage l = PoolStorage.layout();
    _update(l);

    int128 spot64x64 = l.getPriceUpdate(block.timestamp);

    require(args.strike64x64 <= spot64x64 << 1, 'Pool: strike > 2x spot');
    require(args.strike64x64 >= spot64x64 >> 1, 'Pool: strike < 0.5x spot');

    (int128 baseCost64x64, int128 feeCost64x64, int128 cLevel64x64) = quote(
      PoolStorage.QuoteArgs(
      args.maturity,
      args.strike64x64,
      spot64x64,
      args.amount,
      args.isCall
    ));

    baseCost = baseCost64x64.toDecimals(_getTokenDecimals(args.isCall));
    feeCost = feeCost64x64.toDecimals(_getTokenDecimals(args.isCall));

    require(baseCost + feeCost <= args.maxCost, 'Pool: excessive slippage');
    _pull(_getPoolToken(args.isCall), baseCost + feeCost);
    emit Purchase(msg.sender, l.base, l.underlying, args.isCall, args.strike64x64, args.maturity, cLevel64x64, args.amount, baseCost, feeCost);

    // mint free liquidity tokens for treasury
    _mint(FEE_RECEIVER_ADDRESS, _getFreeLiquidityTokenId(args.isCall), feeCost, '');

    // mint long option token for buyer
    _mint(msg.sender, PoolStorage.formatTokenId(_getTokenType(args.isCall, true), args.maturity, args.strike64x64), args.amount, '');

    {
      uint256 shortTokenId = PoolStorage.formatTokenId(_getTokenType(args.isCall, false), args.maturity, args.strike64x64);
      _writeLoop(l, args.amount, baseCost, shortTokenId, args.isCall);
    }

    // update C-Level, accounting for slippage and reinvested premia separately

    int128 totalSupply64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(args.isCall));
    int128 oldTotalSupply64x64 = totalSupply64x64.sub(baseCost64x64).sub(feeCost64x64);

    l.setCLevel(OptionMath.calculateCLevel(
      cLevel64x64, // C-Level after liquidity is reserved
      totalSupply64x64.sub(baseCost64x64).sub(feeCost64x64),
      totalSupply64x64,
      OptionMath.ONE_64x64
    ), args.isCall);

    emit UpdateCLevel(l.base, l.underlying, args.isCall, l.getCLevel(args.isCall), oldTotalSupply64x64, totalSupply64x64);
  }

  /**
   * @notice exercise call option
   * @param args arguments for the exercise function
   */
  function exercise (
    PoolStorage.ExerciseArgs memory args
  ) public {
    uint64 maturity;
    int128 strike64x64;

    {
      PoolStorage.TokenType tokenType;
      (tokenType, maturity, strike64x64) = PoolStorage.parseTokenId(args.longTokenId);
      require(tokenType == PoolStorage.TokenType.LONG_CALL || tokenType == PoolStorage.TokenType.LONG_PUT, 'Pool: invalid token type');
    }

    PoolStorage.Layout storage l = PoolStorage.layout();
    _update(l);

    int128 spot64x64 = l.getPriceUpdateAfter(
      maturity < block.timestamp ? maturity : block.timestamp
    );

    // burn long option tokens from sender
    _burn(msg.sender, args.longTokenId, args.amount);

    uint256 exerciseValue;

    require(spot64x64 > strike64x64, 'Pool: not ITM');

    // option has a non-zero exercise value
    exerciseValue = spot64x64.sub(strike64x64).div(spot64x64).mulu(args.amount);
    _push(_getPoolToken(args.isCall), exerciseValue);

    int128 oldLiquidity64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(args.isCall));

    _exerciseLoop(
      l,
      args.amount,
      exerciseValue,
      PoolStorage.formatTokenId(_getTokenType(args.isCall, false), maturity, strike64x64),
      args.isCall
    );

    int128 newLiquidity64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(args.isCall));

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64, args.isCall);

    emit Exercise(msg.sender, l.base, l.underlying, args.isCall, spot64x64, strike64x64, maturity, args.amount, newLiquidity64x64 - oldLiquidity64x64, exerciseValue);
    emit UpdateCLevel(l.base, l.underlying, args.isCall, l.getCLevel(args.isCall), oldLiquidity64x64, newLiquidity64x64);
  }

  /**
   * @notice deposit underlying currency, underwriting calls of that currency with respect to base currency
   * @param amount quantity of underlying currency to deposit
   * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
   */
  function deposit (
    uint256 amount,
    bool isCallPool
  ) external payable {
    PoolStorage.Layout storage l = PoolStorage.layout();

    l.depositedAt[msg.sender][isCallPool] = block.timestamp;
    _pull(_getPoolToken(isCallPool), amount);

    emit Deposit(msg.sender, l.base, l.underlying, isCallPool, amount);

    uint256 tokenId = _getFreeLiquidityTokenId(isCallPool);

    int128 oldLiquidity64x64 = l.totalSupply64x64(tokenId);
    // mint free liquidity tokens for sender
    _mint(msg.sender, tokenId, amount, '');
    int128 newLiquidity64x64 = l.totalSupply64x64(tokenId);

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64, isCallPool);

    emit UpdateCLevel(l.base, l.underlying, isCallPool, l.getCLevel(isCallPool), oldLiquidity64x64, newLiquidity64x64);
  }

  /**
   * @notice redeem pool share tokens for underlying asset
   * @param amount quantity of share tokens to redeem
   * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
   */
  function withdraw (
    uint256 amount,
    bool isCallPool
  ) external {
    uint256 freeLiqTokenId = _getFreeLiquidityTokenId(isCallPool);
    PoolStorage.Layout storage l = PoolStorage.layout();

    uint256 depositedAt = l.depositedAt[msg.sender][isCallPool];

    require(depositedAt + (1 days) < block.timestamp, 'Pool: liq must be locked 1 day');

    int128 oldLiquidity64x64 = l.totalSupply64x64(freeLiqTokenId);
    // burn free liquidity tokens from sender
    _burn(msg.sender, freeLiqTokenId, amount);
    int128 newLiquidity64x64 = l.totalSupply64x64(freeLiqTokenId);

    _push(_getPoolToken(isCallPool), amount);
    emit Withdrawal(msg.sender, l.base, l.underlying, isCallPool, depositedAt, amount);

    l.setCLevel(oldLiquidity64x64, newLiquidity64x64, isCallPool);

    emit UpdateCLevel(l.base, l.underlying, isCallPool, l.getCLevel(isCallPool), oldLiquidity64x64, newLiquidity64x64);
  }

  /**
   * @notice reassign short position to new liquidity provider
   * @param shortTokenId ERC1155 short token id
   * @param amount quantity of option contract tokens to reassign
   * @param isCall true for call, false for put
   * @return baseCost quantity of tokens required to reassign short position
   * @return feeCost quantity of tokens required to pay fees
   */
  function reassign (
    uint256 shortTokenId,
    uint256 amount,
    bool isCall
  ) external returns (uint256 baseCost, uint256 feeCost) {

    uint64 maturity;
    int128 strike64x64;

    {
      PoolStorage.TokenType tokenType;
      (tokenType, maturity, strike64x64) = PoolStorage.parseTokenId(shortTokenId);
      require(tokenType == PoolStorage.TokenType.SHORT_CALL || tokenType == PoolStorage.TokenType.SHORT_PUT, 'Pool: invalid token type');
      require(maturity > block.timestamp, 'Pool: option expired');
    }

    // TODO: allow exit of expired position

    PoolStorage.Layout storage l = PoolStorage.layout();
    _update(l);

    (int128 baseCost64x64, int128 feeCost64x64, int128 cLevel64x64) = quote(
      PoolStorage.QuoteArgs(maturity,
      strike64x64,
      l.getPriceUpdate(block.timestamp),
      amount,
      isCall
    ));

    baseCost = baseCost64x64.toDecimals(_getTokenDecimals(isCall));
    feeCost = feeCost64x64.toDecimals(_getTokenDecimals(isCall));
    _push(_getPoolToken(isCall), amount - baseCost - feeCost);
    // TODO: reassignment event

    // update C-Level, accounting for slippage and reinvested premia separately

    { // To avoid stack too deep error
      int128 totalSupply64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(isCall));
      int128 newTotalSupply64x64 = totalSupply64x64.add(baseCost64x64).add(feeCost64x64);

      l.setCLevel(OptionMath.calculateCLevel(
          cLevel64x64, // C-Level after liquidity is reserved
          totalSupply64x64,
          newTotalSupply64x64,
          OptionMath.ONE_64x64
        ), isCall);

      emit UpdateCLevel(l.base, l.underlying, isCall, l.getCLevel(isCall), totalSupply64x64, newTotalSupply64x64);
    }

    // mint free liquidity tokens for treasury
    _mint(FEE_RECEIVER_ADDRESS, _getFreeLiquidityTokenId(isCall), feeCost, '');

    // burn short option tokens from underwriter
    _burn(msg.sender, shortTokenId, amount);

    _writeLoop(l, amount, baseCost, shortTokenId, isCall);

    emit Reassign(msg.sender, l.base, l.underlying, isCall, shortTokenId, amount, baseCost, feeCost, cLevel64x64, l.getPriceUpdate(block.timestamp));
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
    uint256 shortTokenId,
    bool isCall
  ) private {

    address underwriter;
    uint256 freeLiqTokenId = _getFreeLiquidityTokenId(isCall);
    (, , int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);

    uint256 toPay = amount;
    if (isCall == false) {
      toPay = strike64x64.mulu(amount);
    }

    while (toPay > 0) {
      underwriter = l.liquidityQueueAscending[underwriter][isCall];

      // amount of liquidity provided by underwriter, accounting for reinvested premium
      uint256 intervalAmount = balanceOf(underwriter, freeLiqTokenId) * (toPay + premium) / toPay;
      if (intervalAmount > toPay) intervalAmount = toPay;

      // amount of premium paid to underwriter
      uint256 intervalPremium = premium * intervalAmount / toPay;
      premium -= intervalPremium;
      toPay -= intervalAmount;

      // burn free liquidity tokens from underwriter
      _burn(underwriter, freeLiqTokenId, intervalAmount - intervalPremium);

      if (isCall == false) {
        intervalAmount = strike64x64.inv().mulu(intervalAmount);
      }

      // mint short option tokens for underwriter
      _mint(underwriter, shortTokenId, toPay == 0 ? amount : intervalAmount, '');
      // To prevent minting less than amount, because of rounding (Can happen for put, because of fixed point precision)
      amount -= intervalAmount;

      emit Underwrite(underwriter, l.base, l.underlying, isCall, shortTokenId, toPay == 0 ? amount : intervalAmount, intervalPremium);
    }
  }

  function _getFreeLiquidityTokenId (
    bool isCall
  ) private view returns (uint256 freeLiqTokenId) {
    freeLiqTokenId = isCall ? UNDERLYING_FREE_LIQ_TOKEN_ID : BASE_FREE_LIQ_TOKEN_ID;
  }

  function _getPoolToken (
    bool isCall
  ) private view returns (address token) {
    token = isCall ? PoolStorage.layout().underlying : PoolStorage.layout().base;
  }

  function _getTokenDecimals (
    bool isCall
  ) private view returns (uint8 decimals) {
    decimals = isCall ? PoolStorage.layout().underlyingDecimals : PoolStorage.layout().baseDecimals;
  }

  function _getTokenType (
    bool isCall,
    bool isLong
  ) private view returns (PoolStorage.TokenType tokenType) {
    if (isCall) {
      tokenType = isLong ? PoolStorage.TokenType.LONG_CALL : PoolStorage.TokenType.SHORT_CALL;
    } else {
      tokenType = isLong ? PoolStorage.TokenType.LONG_PUT : PoolStorage.TokenType.SHORT_PUT;
    }
  }

  function _exerciseLoop (
    PoolStorage.Layout storage l,
    uint256 amount,
    uint256 exerciseValue,
    uint256 shortTokenId,
    bool isCall
  ) private {
    EnumerableSet.AddressSet storage underwriters = ERC1155EnumerableStorage.layout().accountsByToken[shortTokenId];

    uint256 amountRemaining = amount - exerciseValue;

    while (amountRemaining > 0) {
      address underwriter = underwriters.at(underwriters.length() - 1);

      // amount of liquidity provided by underwriter
      uint256 intervalAmount = balanceOf(underwriter, shortTokenId);
      if (intervalAmount > amountRemaining) intervalAmount = amountRemaining;

      // amount of liquidity returned to underwriter, accounting for premium earned by buyer
      uint256 freedAmount = intervalAmount * (amount - exerciseValue) / amount;
      amountRemaining -= freedAmount;

      // mint free liquidity tokens for underwriter
      _mint(underwriter, _getFreeLiquidityTokenId(isCall), freedAmount, '');
      // burn short option tokens from underwriter
      _burn(underwriter, shortTokenId, intervalAmount);

      emit AssignExercise(underwriter, l.base, l.underlying, isCall, shortTokenId, freedAmount, intervalAmount);
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
      l.setPriceUpdate(newPrice64x64);
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

    for (uint256 i; i < ids.length; i++) {
      if (ids[i] == UNDERLYING_FREE_LIQ_TOKEN_ID || ids[i] == BASE_FREE_LIQ_TOKEN_ID) {
        if (amounts[i] > 0) {
          bool isCallPool = ids[i] == UNDERLYING_FREE_LIQ_TOKEN_ID;

          PoolStorage.Layout storage l = PoolStorage.layout();

          if (from != address(0) && balanceOf(from, ids[i]) == amounts[i]) {
            l.removeUnderwriter(from, isCallPool);
          }

          if (to != address(0) && balanceOf(to, ids[i]) == 0) {
            l.addUnderwriter(to, isCallPool);
          }
        }
      }
    }
  }
}
