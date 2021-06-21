// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { OwnableInternal } from '@solidstate/contracts/access/OwnableInternal.sol';
import { IERC20 } from '@solidstate/contracts/token/ERC20/IERC20.sol';
import { ERC1155Enumerable, EnumerableSet, ERC1155EnumerableStorage } from '@solidstate/contracts/token/ERC1155/ERC1155Enumerable.sol';
import { IWETH } from '@solidstate/contracts/utils/IWETH.sol';

import { PoolStorage } from './PoolStorage.sol';

import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';
import { ABDKMath64x64Token } from '../libraries/ABDKMath64x64Token.sol';
import { OptionMath } from '../libraries/OptionMath.sol';

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is OwnableInternal, ERC1155Enumerable {
  using ABDKMath64x64 for int128;
  using EnumerableSet for EnumerableSet.AddressSet;
  using PoolStorage for PoolStorage.Layout;

  address private immutable WETH_ADDRESS;
  address private immutable FEE_RECEIVER_ADDRESS;

  int128 private immutable FEE_64x64;

  uint256 private immutable UNDERLYING_FREE_LIQ_TOKEN_ID;
  uint256 private immutable BASE_FREE_LIQ_TOKEN_ID;

  event Purchase (
    address indexed user,
    uint256 longTokenId,
    uint256 amount,
    uint256 baseCost,
    uint256 feeCost,
    int128 spot64x64
  );

  event Exercise (
    address indexed user,
    uint256 longTokenId,
    uint256 amount,
    uint256 exerciseValue
  );

  event Underwrite (
    address indexed underwriter,
    uint256 shortTokenId,
    uint256 intervalAmount,
    uint256 intervalPremium
  );

  event AssignExercise (
    address indexed underwriter,
    uint256 shortTokenId,
    uint256 freedAmount,
    uint256 intervalAmount
  );

  event Reassign (
    address indexed underwriter,
    uint256 shortTokenId,
    uint256 amount,
    uint256 baseCost,
    uint256 feeCost,
    int128 cLevel64x64,
    int128 spot64x64
  );

  event Deposit (
    address indexed user,
    bool isCallPool,
    uint256 amount
  );

  event Withdrawal (
    address indexed user,
    bool isCallPool,
    uint256 depositedAt,
    uint256 amount
  );

  event UpdateCLevel (
    bool indexed isCall,
    int128 cLevel64x64,
    int128 oldLiquidity64x64,
    int128 newLiquidity64x64
  );

  event UpdateVariance (
    int128 oldEmaLogReturns64x64,
    int128 oldEmaVariance64x64,
    int128 logReturns64x64,
    uint256 oldTimestamp,
    int128 emaVarianceAnnualized64x64
  );

  constructor (
    address weth,
    address feeReceiver,
    int128 fee64x64
  ) {
    WETH_ADDRESS = weth;
    FEE_RECEIVER_ADDRESS = feeReceiver;
    FEE_64x64 = fee64x64;
    UNDERLYING_FREE_LIQ_TOKEN_ID = PoolStorage.formatTokenId(PoolStorage.TokenType.UNDERLYING_FREE_LIQ, 0, 0);
    BASE_FREE_LIQ_TOKEN_ID = PoolStorage.formatTokenId(PoolStorage.TokenType.BASE_FREE_LIQ, 0, 0);
  }

  /**
    * @notice get pool settings
    * @return pool settings
    */
  function getPoolSettings () external view returns (PoolStorage.PoolSettings memory) {
    PoolStorage.Layout storage l = PoolStorage.layout();
    return PoolStorage.PoolSettings(
      l.underlying,
      l.base,
      l.underlyingOracle,
      l.baseOracle
    );
  }

  /**
   * @notice get C Level
   * @return 64x64 fixed point representation of C-Level of Pool after purchase
   */
  function getCLevel64x64 (bool isCall) external view returns (int128) {
    return PoolStorage.layout().getCLevel(isCall);
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
   * @notice get parameters for token id
   * @return parameters for token id
   */
  function getParametersForTokenId (uint256 tokenId) external pure returns (PoolStorage.TokenType, uint64, int128) {
    return PoolStorage.parseTokenId(tokenId);
  }

  /**
   * @notice calculate price of option contract
   * @param args arguments of the quote
   * @return baseCost64x64 64x64 fixed point representation of option cost denominated in underlying currency (without fee)
   * @return feeCost64x64 64x64 fixed point representation of option fee cost denominated in underlying currency for call, or base currency for put
   * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
   * @return slippageCoefficient64x64 64x64 fixed point representation of slippage coefficient for given order size
   */
  function quote (
    PoolStorage.QuoteArgs memory args
  ) public view returns (int128 baseCost64x64, int128 feeCost64x64, int128 cLevel64x64, int128 slippageCoefficient64x64) {
    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 amount64x64 = ABDKMath64x64Token.fromDecimals(args.amount, l.underlyingDecimals);
    bool isCall = args.isCall;

    int128 oldLiquidity64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(isCall));
    require(oldLiquidity64x64 > 0, "no liq");

    // TODO: validate values without spending gas
    // assert(oldLiquidity64x64 >= newLiquidity64x64);
    // assert(variance64x64 > 0);
    // assert(strike64x64 > 0);
    // assert(spot64x64 > 0);
    // assert(timeToMaturity64x64 > 0);

    int128 price64x64;

    (price64x64, cLevel64x64, slippageCoefficient64x64) = OptionMath.quotePrice(
      l.emaVarianceAnnualized64x64,
      args.strike64x64,
      args.spot64x64,
      ABDKMath64x64.divu(args.maturity - block.timestamp, 365 days),
      isCall ? l.cLevelUnderlying64x64 : l.cLevelBase64x64,
      oldLiquidity64x64,
      oldLiquidity64x64.sub(amount64x64),
      OptionMath.ONE_64x64,
      isCall
    );

    baseCost64x64 = isCall ? price64x64.mul(amount64x64).div(args.spot64x64) : price64x64.mul(amount64x64);
    feeCost64x64 = baseCost64x64.mul(FEE_64x64);
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

    PoolStorage.Layout storage l = PoolStorage.layout();

    {
      uint256 amount = args.isCall
        ? args.amount
        : l.fromUnderlyingToBaseDecimals(args.strike64x64.mulu(args.amount));

      require(amount <= totalSupply(_getFreeLiquidityTokenId(args.isCall)), 'insuf liq');
    }

    require(args.maturity >= block.timestamp + (1 days), 'exp < 1 day');
    require(args.maturity < block.timestamp + (29 days), 'exp > 28 days');
    require(args.maturity % (1 days) == 0, 'exp not end UTC day');

    int128 newPrice64x64 = _update(l);

    require(args.strike64x64 <= newPrice64x64 << 1, 'strike > 2x spot');
    require(args.strike64x64 >= newPrice64x64 >> 1, 'strike < 0.5x spot');

    int128 cLevel64x64;
    int128 totalSupply64x64;
    int128 oldTotalSupply64x64;

    {
      int128 baseCost64x64;
      int128 feeCost64x64;

      (baseCost64x64, feeCost64x64, cLevel64x64,) = quote(
        PoolStorage.QuoteArgs(
        args.maturity,
        args.strike64x64,
        newPrice64x64,
        args.amount,
        args.isCall
      ));

      baseCost = ABDKMath64x64Token.toDecimals(baseCost64x64, _getTokenDecimals(args.isCall));
      feeCost = ABDKMath64x64Token.toDecimals(feeCost64x64, _getTokenDecimals(args.isCall));

      totalSupply64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(args.isCall));
      oldTotalSupply64x64 = totalSupply64x64.sub(baseCost64x64).sub(feeCost64x64);
    }

    require(baseCost + feeCost <= args.maxCost, 'excess slipp');
    _pull(_getPoolToken(args.isCall), baseCost + feeCost);

    {
      uint256 longTokenId = PoolStorage.formatTokenId(_getTokenType(args.isCall, true), args.maturity, args.strike64x64);

      emit Purchase(
        msg.sender,
        longTokenId,
        args.amount,
        baseCost,
        feeCost,
        newPrice64x64
      );

      // mint free liquidity tokens for treasury
      _mint(FEE_RECEIVER_ADDRESS, _getFreeLiquidityTokenId(args.isCall), feeCost, '');

      // mint long option token for buyer
      _mint(msg.sender, longTokenId, args.amount, '');
    }

    {
      uint256 shortTokenId = PoolStorage.formatTokenId(_getTokenType(args.isCall, false), args.maturity, args.strike64x64);
      _mintShortTokenLoop(l, args.amount, baseCost, shortTokenId, args.isCall);
    }

    // update C-Level, accounting for slippage and reinvested premia separately
    _setCLevel(l, OptionMath.calculateCLevel(
      cLevel64x64, // C-Level after liquidity is reserved
      oldTotalSupply64x64,
      totalSupply64x64,
      OptionMath.ONE_64x64
    ), oldTotalSupply64x64, totalSupply64x64, args.isCall);
  }

  /**
   * @notice exercise call option on behalf of holder
   * @param holder owner of long option tokens to exercise
   * @param longTokenId long option token id
   * @param amount quantity of tokens to exercise
   */
  function exerciseFrom (
    address holder,
    uint256 longTokenId,
    uint256 amount
  ) external {
    if (msg.sender != holder) {
      require(isApprovedForAll(holder, msg.sender), "not approved");
    }

    _exercise(holder, longTokenId, amount);
  }

  /**
   * @notice process expired option, freeing liquidity and distributing profits
   * @param longTokenId long option token id
   * @param amount quantity of tokens to process
   */
  function processExpired (
    uint256 longTokenId,
    uint256 amount
  ) external {
    _exercise(address(0), longTokenId, amount);
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

    emit Deposit(msg.sender, isCallPool, amount);

    uint256 tokenId = _getFreeLiquidityTokenId(isCallPool);

    int128 oldLiquidity64x64 = l.totalSupply64x64(tokenId);
    // mint free liquidity tokens for sender
    _mint(msg.sender, tokenId, amount, '');
    int128 newLiquidity64x64 = l.totalSupply64x64(tokenId);

    _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCallPool);
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

    require(depositedAt + (1 days) < block.timestamp, 'liq lock 1d');

    int128 oldLiquidity64x64 = l.totalSupply64x64(freeLiqTokenId);
    // burn free liquidity tokens from sender
    _burn(msg.sender, freeLiqTokenId, amount);
    int128 newLiquidity64x64 = l.totalSupply64x64(freeLiqTokenId);

    _pushTo(msg.sender, _getPoolToken(isCallPool), amount);
    emit Withdrawal(msg.sender, isCallPool, depositedAt, amount);

    _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCallPool);
  }


  /**
   * @notice reassign short position to new liquidity provider
   * @param shortTokenId ERC1155 short token id
   * @param amount quantity of option contract tokens to reassign
   * @return baseCost quantity of tokens required to reassign short position
   * @return feeCost quantity of tokens required to pay fees
   */
  function reassign (
    uint256 shortTokenId,
    uint256 amount
  ) external returns (uint256 baseCost, uint256 feeCost) {
    uint64 maturity;
    int128 strike64x64;
    bool isCall;

    {
      PoolStorage.TokenType tokenType;
      (tokenType, maturity, strike64x64) = PoolStorage.parseTokenId(shortTokenId);
      require(tokenType == PoolStorage.TokenType.SHORT_CALL || tokenType == PoolStorage.TokenType.SHORT_PUT, 'invalid type');
      require(maturity > block.timestamp, 'expired');

      isCall = tokenType == PoolStorage.TokenType.SHORT_CALL;
    }

    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 newPrice64x64 = _update(l);
    int128 cLevel64x64;

    { // To avoid stack too deep
      int128 baseCost64x64;
      int128 feeCost64x64;

      (baseCost64x64, feeCost64x64, cLevel64x64,) = quote(PoolStorage.QuoteArgs(
        maturity,
        strike64x64,
        newPrice64x64,
        amount,
        isCall
      ));

      baseCost = ABDKMath64x64Token.toDecimals(baseCost64x64, _getTokenDecimals(isCall));
      feeCost = ABDKMath64x64Token.toDecimals(feeCost64x64, _getTokenDecimals(isCall));

      uint256 pushAmount = isCall ? amount : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(amount));

      _pushTo(
        msg.sender,
        _getPoolToken(isCall),
        pushAmount - baseCost - feeCost
      );

      // update C-Level, accounting for slippage and reinvested premia separately
      _updateCLevelReassign(isCall, baseCost64x64, feeCost64x64, cLevel64x64);
    }

    // mint free liquidity tokens for treasury
    _mint(FEE_RECEIVER_ADDRESS, _getFreeLiquidityTokenId(isCall), feeCost, '');

    // burn short option tokens from underwriter
    _burn(msg.sender, shortTokenId, amount);

    _mintShortTokenLoop(l, amount, baseCost, shortTokenId, isCall);

    emit Reassign(
      msg.sender,
      shortTokenId,
      amount,
      baseCost,
      feeCost,
      cLevel64x64,
      newPrice64x64
    );
  }

  /**
   * @notice Update pool data
   */
  function update () external {
    _update(PoolStorage.layout());
  }

  ////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////

  //////////////
  // Internal //
  //////////////

  function _updateCLevelReassign (bool isCall, int128 baseCost64x64, int128 feeCost64x64, int128 cLevel64x64) internal {
    PoolStorage.Layout storage l = PoolStorage.layout();
    int128 totalSupply64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(isCall));
    int128 newTotalSupply64x64 = totalSupply64x64.add(baseCost64x64).add(feeCost64x64);

    int128 newCLevel64x64 = OptionMath.calculateCLevel(
      cLevel64x64, // C-Level after liquidity is reserved
      totalSupply64x64,
      newTotalSupply64x64,
      OptionMath.ONE_64x64
    );

    _setCLevel(l, newCLevel64x64, totalSupply64x64, newTotalSupply64x64, isCall);
  }

  function _exercise (
    address holder, // holder address of option contract tokens to exercise
    uint256 longTokenId, // amount quantity of option contract tokens to exercise
    uint256 amount // quantity of option contract tokens to exercise
  ) internal {
    uint64 maturity;
    int128 strike64x64;
    bool isCall;

    bool onlyExpired = holder == address(0);

    {
      PoolStorage.TokenType tokenType;
      (tokenType, maturity, strike64x64) = PoolStorage.parseTokenId(longTokenId);
      require(tokenType == PoolStorage.TokenType.LONG_CALL || tokenType == PoolStorage.TokenType.LONG_PUT, 'invalid type');
      require(!onlyExpired || maturity < block.timestamp, 'not expired');
      isCall = tokenType == PoolStorage.TokenType.LONG_CALL;
    }

    PoolStorage.Layout storage l = PoolStorage.layout();
    int128 spot64x64 = _update(l);

    if (maturity < block.timestamp) {
      spot64x64 = l.getPriceUpdateAfter(maturity);
    }

    require(onlyExpired || (isCall ? (spot64x64 > strike64x64) : (spot64x64 < strike64x64)), 'not ITM');

    uint256 exerciseValue;
    // option has a non-zero exercise value
    if (isCall) {
      if (spot64x64 > strike64x64) {
        exerciseValue = spot64x64.sub(strike64x64).div(spot64x64).mulu(amount);
      }
    } else {
      if (spot64x64 < strike64x64) {
        exerciseValue = l.fromUnderlyingToBaseDecimals(strike64x64.sub(spot64x64).mulu(amount));
      }
    }

    if (onlyExpired) {
      _burnLongTokenLoop(
        amount,
        isCall ? exerciseValue : strike64x64.inv().mulu(exerciseValue),
        longTokenId,
        isCall
      );
    } else {
      // burn long option tokens from sender
      _burn(holder, longTokenId, amount);

      if (exerciseValue > 0) {
        _pushTo(holder, _getPoolToken(isCall), exerciseValue);

        emit Exercise(
          holder,
          longTokenId,
          amount,
          exerciseValue
        );
      }
    }

    int128 oldLiquidity64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(isCall));

    _burnShortTokenLoop(
      amount,
      isCall ? exerciseValue : strike64x64.inv().mulu(exerciseValue),
      PoolStorage.formatTokenId(_getTokenType(isCall, false), maturity, strike64x64),
      isCall
    );

    int128 newLiquidity64x64 = l.totalSupply64x64(_getFreeLiquidityTokenId(isCall));

    _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCall);
  }

  function _mintShortTokenLoop (
    PoolStorage.Layout storage l,
    uint256 amount,
    uint256 premium,
    uint256 shortTokenId,
    bool isCall
  ) private {
    address underwriter;
    uint256 freeLiqTokenId = _getFreeLiquidityTokenId(isCall);
    (, , int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);

    uint256 toPay = isCall ? amount : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(amount));

    while (toPay > 0) {
      underwriter = l.liquidityQueueAscending[underwriter][isCall];

      // ToDo : Do we keep this ?
      if (underwriter == msg.sender) continue;

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
        intervalAmount = l.fromBaseToUnderlyingDecimals(strike64x64.inv().mulu(intervalAmount));
      }

      // mint short option tokens for underwriter
      // toPay == 0 ? amount : intervalAmount : To prevent minting less than amount,
      // because of rounding (Can happen for put, because of fixed point precision)
      _mint(underwriter, shortTokenId, toPay == 0 ? amount : intervalAmount, '');

      emit Underwrite(underwriter, shortTokenId, toPay == 0 ? amount : intervalAmount, intervalPremium);

      amount -= intervalAmount;
    }
  }

  function _burnLongTokenLoop (
    uint256 amount,
    uint256 exerciseValue,
    uint256 longTokenId,
    bool isCall
  ) internal {
    EnumerableSet.AddressSet storage holders = ERC1155EnumerableStorage.layout().accountsByToken[longTokenId];

    while (amount > 0) {
      address longTokenHolder = holders.at(holders.length() - 1);

      uint256 intervalAmount = balanceOf(longTokenHolder, longTokenId);
      if (intervalAmount > amount) intervalAmount = amount;

      uint256 intervalExerciseValue;

      if (exerciseValue > 0) {
        intervalExerciseValue = exerciseValue * intervalAmount / amount;
        exerciseValue -= intervalExerciseValue;
        _pushTo(longTokenHolder, _getPoolToken(isCall), intervalExerciseValue);
      }

      amount -= intervalAmount;

      emit Exercise (
        longTokenHolder,
        longTokenId,
        intervalAmount,
        intervalExerciseValue
      );

      _burn(longTokenHolder, longTokenId, intervalAmount);
    }
  }

  function _burnShortTokenLoop (
    uint256 amount,
    uint256 exerciseValue,
    uint256 shortTokenId,
    bool isCall
  ) private {
    EnumerableSet.AddressSet storage underwriters = ERC1155EnumerableStorage.layout().accountsByToken[shortTokenId];
    (, , int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);

    while (amount > 0) {
      address underwriter = underwriters.at(underwriters.length() - 1);

      // amount of liquidity provided by underwriter
      uint256 intervalAmount = balanceOf(underwriter, shortTokenId);
      if (intervalAmount > amount) intervalAmount = amount;

      // amount of value claimed by buyer
      uint256 intervalExerciseValue = exerciseValue * intervalAmount / amount;
      exerciseValue -= intervalExerciseValue;
      amount -= intervalAmount;

      uint256 freeLiq = isCall
        ? intervalAmount - intervalExerciseValue
        : PoolStorage.layout().fromUnderlyingToBaseDecimals(strike64x64.mulu(intervalAmount)) - intervalExerciseValue;


      // mint free liquidity tokens for underwriter
      _mint(underwriter, _getFreeLiquidityTokenId(isCall), freeLiq, '');
      // burn short option tokens from underwriter
      _burn(underwriter, shortTokenId, intervalAmount);

      emit AssignExercise(underwriter, shortTokenId, freeLiq, intervalAmount);
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
  ) private pure returns (PoolStorage.TokenType tokenType) {
    if (isCall) {
      tokenType = isLong ? PoolStorage.TokenType.LONG_CALL : PoolStorage.TokenType.SHORT_CALL;
    } else {
      tokenType = isLong ? PoolStorage.TokenType.LONG_PUT : PoolStorage.TokenType.SHORT_PUT;
    }
  }

  function _setCLevel (
    PoolStorage.Layout storage l,
    int128 oldLiquidity64x64,
    int128 newLiquidity64x64,
    bool isCallPool
  ) internal {
    l.setCLevel(oldLiquidity64x64, newLiquidity64x64, isCallPool);
    emit UpdateCLevel(isCallPool, l.getCLevel(isCallPool), oldLiquidity64x64, newLiquidity64x64);
  }

  function _setCLevel (
    PoolStorage.Layout storage l,
    int128 cLevel64x64,
    int128 oldLiquidity64x64,
    int128 newLiquidity64x64,
    bool isCallPool
  ) internal {
    l.setCLevel(cLevel64x64, isCallPool);
    emit UpdateCLevel(isCallPool, cLevel64x64, oldLiquidity64x64, newLiquidity64x64);
  }

  /**
   * @notice TODO
   */
  function _update (
    PoolStorage.Layout storage l
  ) internal returns (int128 newPrice64x64) {
    newPrice64x64 = l.fetchPriceUpdate();

    uint256 updatedAt = l.updatedAt;

    int128 oldPrice64x64 = l.getPriceUpdate(updatedAt);

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

    int128 oldEmaVarianceAnnualized64x64 = l.emaVarianceAnnualized64x64;
    int128 newEmaVarianceAnnualized64x64 = OptionMath.unevenRollingEmaVariance(
      oldEmaLogReturns64x64,
      oldEmaVarianceAnnualized64x64 / 365,
      logReturns64x64,
      updatedAt,
      block.timestamp
    ) * 365;

    l.emaVarianceAnnualized64x64 = newEmaVarianceAnnualized64x64;

    emit UpdateVariance(
      oldEmaLogReturns64x64,
      oldEmaVarianceAnnualized64x64 / 365,
      logReturns64x64,
      updatedAt,
      newEmaVarianceAnnualized64x64
    );

    l.updatedAt = block.timestamp;
  }

  /**
   * @notice transfer ERC20 tokens to message sender
   * @param token ERC20 token address
   * @param amount quantity of token to transfer
   */
  function _pushTo (
    address to,
    address token,
    uint256 amount
  ) internal {
    require(
      IERC20(token).transfer(to, amount),
      'ERC20 transfer failed'
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
        require(msg.value <= amount, "too much ETH sent");

        unchecked {
          amount -= msg.value;
        }

        IWETH(WETH_ADDRESS).deposit{ value: msg.value }();
      }
    } else {
      require(
        msg.value == 0,
        'not WETH deposit'
      );
    }

    if (amount > 0) {
      require(
        IERC20(token).transferFrom(msg.sender, address(this), amount),
        'ERC20 transfer failed'
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
  ) virtual override internal {
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