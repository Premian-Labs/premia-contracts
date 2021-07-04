// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { OwnableInternal } from '@solidstate/contracts/access/OwnableInternal.sol';
import { ERC165 } from '@solidstate/contracts/introspection/ERC165.sol';
import { IERC20 } from '@solidstate/contracts/token/ERC20/IERC20.sol';
import { ERC1155Enumerable, EnumerableSet, ERC1155EnumerableStorage } from '@solidstate/contracts/token/ERC1155/ERC1155Enumerable.sol';
import { IWETH } from '@solidstate/contracts/utils/IWETH.sol';

import { PoolStorage } from './PoolStorage.sol';

import { ABDKMath64x64 } from 'abdk-libraries-solidity/ABDKMath64x64.sol';
import { ABDKMath64x64Token } from '../libraries/ABDKMath64x64Token.sol';
import {OptionMath} from '../libraries/OptionMath.sol';

/**
 * @title Premia option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is OwnableInternal, ERC1155Enumerable, ERC165 {
  using ABDKMath64x64 for int128;
  using EnumerableSet for EnumerableSet.AddressSet;
  using PoolStorage for PoolStorage.Layout;

  address private immutable WETH_ADDRESS;
  address private immutable FEE_RECEIVER_ADDRESS;

  int128 private immutable FEE_64x64;
  uint256 private immutable BATCHING_PERIOD;

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
    int128 fee64x64,
    uint256 batchingPeriod
  ) {
    WETH_ADDRESS = weth;
    FEE_RECEIVER_ADDRESS = feeReceiver;
    FEE_64x64 = fee64x64;
    BATCHING_PERIOD = batchingPeriod;
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
  ) external view returns (
    int128 baseCost64x64,
    int128 feeCost64x64,
    int128 cLevel64x64,
    int128 slippageCoefficient64x64
  ) {
    (
      baseCost64x64,
      feeCost64x64,
      cLevel64x64,
      slippageCoefficient64x64
    ) = _quote(args);
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

    bool isCall = args.isCall;

    PoolStorage.Layout storage l = PoolStorage.layout();

    _processPendingDeposits(l, isCall);

    {
      uint256 amount = isCall
        ? args.amount
        : l.fromUnderlyingToBaseDecimals(args.strike64x64.mulu(args.amount));

      require(amount <= totalSupply(_getFreeLiquidityTokenId(isCall)) - l.nextDeposits[isCall].totalPendingDeposits, 'insuf liq');
    }

    require(args.maturity >= block.timestamp + (1 days), 'exp < 1 day');
    require(args.maturity < block.timestamp + (29 days), 'exp > 28 days');
    require(args.maturity % (1 days) == 0, 'exp not end UTC day');

    (int128 newPrice64x64,) = _update(l);

    require(args.strike64x64 <= newPrice64x64 * 3 / 2, 'strike > 1.5x spot');
    require(args.strike64x64 >= newPrice64x64 * 3 / 4, 'strike < 0.75x spot');

    int128 cLevel64x64;

    {
      int128 baseCost64x64;
      int128 feeCost64x64;

      (baseCost64x64, feeCost64x64, cLevel64x64,) = _quote(
        PoolStorage.QuoteArgs(
          args.maturity,
          args.strike64x64,
          newPrice64x64,
          l.emaVarianceAnnualized64x64,
          args.amount,
          isCall
        )
      );

      baseCost = ABDKMath64x64Token.toDecimals(baseCost64x64, l.getTokenDecimals(isCall));
      feeCost = ABDKMath64x64Token.toDecimals(feeCost64x64, l.getTokenDecimals(isCall));
    }

    require(baseCost + feeCost <= args.maxCost, 'excess slipp');
    _pull(_getPoolToken(isCall), baseCost + feeCost);

    {
      uint256 longTokenId = PoolStorage.formatTokenId(_getTokenType(isCall, true), args.maturity, args.strike64x64);

      emit Purchase(
        msg.sender,
        longTokenId,
        args.amount,
        baseCost,
        feeCost,
        newPrice64x64
      );

      // mint long option token for buyer
      _mint(msg.sender, longTokenId, args.amount);
    }

    uint256 shortTokenId = PoolStorage.formatTokenId(_getTokenType(isCall, false), args.maturity, args.strike64x64);

    int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);
    // burn free liquidity tokens from other underwriters
    _mintShortTokenLoop(l, args.amount, baseCost, shortTokenId, isCall);
    int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

    _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCall);

    // mint free liquidity tokens for treasury
    _mint(FEE_RECEIVER_ADDRESS, _getFreeLiquidityTokenId(isCall), feeCost);
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

    _processPendingDeposits(l, isCallPool);

    l.depositedAt[msg.sender][isCallPool] = block.timestamp;
    _pull(_getPoolToken(isCallPool), amount);

    _addToDepositQueue(msg.sender, amount, isCallPool);

    emit Deposit(msg.sender, isCallPool, amount);
  }

  /**
   * @notice redeem pool share tokens for underlying asset
   * @param amount quantity of share tokens to redeem
   * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
   */
  function withdraw (
    uint256 amount,
    bool isCallPool
  ) public {
    PoolStorage.Layout storage l = PoolStorage.layout();

    _processPendingDeposits(l, isCallPool);

    uint256 depositedAt = l.depositedAt[msg.sender][isCallPool];

    require(depositedAt + (1 days) < block.timestamp, 'liq lock 1d');

    int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCallPool);
    // burn free liquidity tokens from sender
    _burn(msg.sender, _getFreeLiquidityTokenId(isCallPool), amount);
    int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCallPool);

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
    (PoolStorage.TokenType tokenType, , ) = PoolStorage.parseTokenId(shortTokenId);
    bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL;

    PoolStorage.Layout storage l = PoolStorage.layout();
    (int128 newPrice64x64, ) = _update(l);

    _processPendingDeposits(l, isCall);
    (baseCost, feeCost) = _reassign(l, shortTokenId, amount, newPrice64x64);
  }

  /**
   * @notice TODO
   */
  function reassignBatch (
    uint256[] calldata ids,
    uint256[] calldata amounts
  ) public returns (uint256[] memory baseCosts, uint256[] memory feeCosts) {
    require(ids.length == amounts.length, 'TODO');

    PoolStorage.Layout storage l = PoolStorage.layout();
    (int128 newPrice64x64, ) = _update(l);

    // process both pools because ids may correspond to both
    _processPendingDeposits(l, true);
    _processPendingDeposits(l, false);

    baseCosts = new uint256[](ids.length);
    feeCosts = new uint256[](ids.length);

    for (uint256 i; i < ids.length; i++) {
      (baseCosts[i], feeCosts[i]) = _reassign(l, ids[i], amounts[i], newPrice64x64);
    }
  }

  /**
   * @notice TODO
   */
  function withdrawAllAndReassignBatch (
    bool isCallPool,
    uint256[] calldata ids,
    uint256[] calldata amounts
  ) external returns (uint256[] memory baseCosts, uint256[] memory feeCosts) {
    uint256 balance = balanceOf(msg.sender, _getFreeLiquidityTokenId(isCallPool));

    if (balance > 0) {
      withdraw(balance, isCallPool);
    }

    (baseCosts, feeCosts) = reassignBatch(ids, amounts);
  }

  /**
   * @notice Update pool data
   */
  function update () external returns(int128 newEmaVarianceAnnualized64x64) {
    (,newEmaVarianceAnnualized64x64) = _update(PoolStorage.layout());
  }

  ////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////

  //////////////
  // Internal //
  //////////////

  /**
   * @notice TODO
   */
  function _quote (
    PoolStorage.QuoteArgs memory args
  ) internal view returns (
    int128 baseCost64x64,
    int128 feeCost64x64,
    int128 cLevel64x64,
    int128 slippageCoefficient64x64
  ) {
    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 amount64x64 = ABDKMath64x64Token.fromDecimals(args.amount, l.underlyingDecimals);
    bool isCall = args.isCall;

    int128 oldLiquidity64x64;

    {
      PoolStorage.BatchData storage batchData = l.nextDeposits[isCall];
      int128 pendingDeposits64x64;

      if (batchData.eta != 0 && block.timestamp >= batchData.eta) {
        pendingDeposits64x64 = ABDKMath64x64Token.fromDecimals(
          batchData.totalPendingDeposits,
          l.getTokenDecimals(isCall)
        );
      }

      oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall).add(pendingDeposits64x64);
      require(oldLiquidity64x64 > 0, "no liq");

      if (pendingDeposits64x64 > 0) {
        cLevel64x64 = l.calculateCLevel(
          oldLiquidity64x64.sub(pendingDeposits64x64),
          oldLiquidity64x64,
          isCall
        );
      } else {
        cLevel64x64 = l.getCLevel(isCall);
      }
    }

    // TODO: validate values without spending gas
    // assert(oldLiquidity64x64 >= newLiquidity64x64);
    // assert(variance64x64 > 0);
    // assert(strike64x64 > 0);
    // assert(spot64x64 > 0);
    // assert(timeToMaturity64x64 > 0);

    int128 price64x64;

    (price64x64, cLevel64x64, slippageCoefficient64x64) = OptionMath.quotePrice(
      OptionMath.QuoteArgs(
        args.emaVarianceAnnualized64x64,
        args.strike64x64,
        args.spot64x64,
        ABDKMath64x64.divu(args.maturity - block.timestamp, 365 days),
        cLevel64x64,
        oldLiquidity64x64,
        oldLiquidity64x64.sub(amount64x64),
        0x10000000000000000, // 64x64 fixed point representation of 1
        isCall
      )
    );

    baseCost64x64 = isCall ? price64x64.mul(amount64x64).div(args.spot64x64) : price64x64.mul(amount64x64);
    feeCost64x64 = baseCost64x64.mul(FEE_64x64);
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

    _processPendingDeposits(l, isCall);

    (int128 spot64x64,) = _update(l);

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
        exerciseValue,
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

    _burnShortTokenLoop(
      amount,
      exerciseValue,
      PoolStorage.formatTokenId(_getTokenType(isCall, false), maturity, strike64x64),
      isCall
    );
  }

  /**
   * @notice TODO
   */
  function _reassign (
    PoolStorage.Layout storage l,
    uint256 shortTokenId,
    uint256 amount,
    int128 newPrice64x64
  ) internal returns (uint256 baseCost, uint256 feeCost) {
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

    int128 cLevel64x64;

    { // To avoid stack too deep
      int128 baseCost64x64;
      int128 feeCost64x64;

      (baseCost64x64, feeCost64x64, cLevel64x64,) = _quote(
        PoolStorage.QuoteArgs(
          maturity,
          strike64x64,
          newPrice64x64,
          l.emaVarianceAnnualized64x64,
          amount,
          isCall
        )
      );

      baseCost = ABDKMath64x64Token.toDecimals(baseCost64x64, l.getTokenDecimals(isCall));
      feeCost = ABDKMath64x64Token.toDecimals(feeCost64x64, l.getTokenDecimals(isCall));

      uint256 pushAmount = isCall ? amount : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(amount));

      _pushTo(
        msg.sender,
        _getPoolToken(isCall),
        pushAmount - baseCost - feeCost
      );
    }

    // burn short option tokens from underwriter
    _burn(msg.sender, shortTokenId, amount);

    int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);
    // burn free liquidity tokens from other underwriters
    _mintShortTokenLoop(l, amount, baseCost, shortTokenId, isCall);
    int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

    _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCall);

    // mint free liquidity tokens for treasury
    _mint(FEE_RECEIVER_ADDRESS, _getFreeLiquidityTokenId(isCall), feeCost);

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

    mapping (address => address) storage queue = l.liquidityQueueAscending[isCall];

    while (toPay > 0) {
      underwriter = queue[address(0)];
      uint256 balance = balanceOf(underwriter, freeLiqTokenId);

      // ToDo : Find better solution ?
      // If dust left, we remove underwriter and skip to next
      if (balance < 1e5) {
        l.removeUnderwriter(underwriter, isCall);
        continue;
      }

      // ToDo : Do we keep this ?
      // if (underwriter == msg.sender) continue;

      // amount of liquidity provided by underwriter, accounting for reinvested premium
      uint256 intervalAmount = (balance - l.pendingDeposits[underwriter][l.nextDeposits[isCall].eta][isCall]) * (toPay + premium) / toPay;
      if (intervalAmount == 0) continue;
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
      _mint(underwriter, shortTokenId, toPay == 0 ? amount : intervalAmount);

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
      _addToDepositQueue(underwriter, freeLiq, isCall);
      // burn short option tokens from underwriter
      _burn(underwriter, shortTokenId, intervalAmount);

      emit AssignExercise(underwriter, shortTokenId, freeLiq, intervalAmount);
    }
  }

  function _addToDepositQueue (
    address account,
    uint256 amount,
    bool isCallPool
  ) internal {
    PoolStorage.Layout storage l = PoolStorage.layout();

    _mint(account, _getFreeLiquidityTokenId(isCallPool), amount);

    uint256 nextBatch = (block.timestamp / BATCHING_PERIOD) * BATCHING_PERIOD + BATCHING_PERIOD;
    l.pendingDeposits[account][nextBatch][isCallPool] += amount;

    PoolStorage.BatchData storage batchData = l.nextDeposits[isCallPool];
    batchData.totalPendingDeposits += amount;
    batchData.eta = nextBatch;
  }

  function _processPendingDeposits (
    PoolStorage.Layout storage l,
    bool isCall
  ) internal {
    PoolStorage.BatchData storage data = l.nextDeposits[isCall];

    if (data.eta == 0 || block.timestamp < data.eta) return;

    int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

    _setCLevel(
      l,
      oldLiquidity64x64,
      oldLiquidity64x64.add(ABDKMath64x64Token.fromDecimals(data.totalPendingDeposits, l.getTokenDecimals(isCall))),
      isCall
    );

    delete l.nextDeposits[isCall];
  }

  function _getFreeLiquidityTokenId (
    bool isCall
  ) internal view returns (uint256 freeLiqTokenId) {
    freeLiqTokenId = isCall ? UNDERLYING_FREE_LIQ_TOKEN_ID : BASE_FREE_LIQ_TOKEN_ID;
  }

  function _getPoolToken (
    bool isCall
  ) private view returns (address token) {
    token = isCall ? PoolStorage.layout().underlying : PoolStorage.layout().base;
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
    int128 cLevel64x64 = l.setCLevel(oldLiquidity64x64, newLiquidity64x64, isCallPool);
    emit UpdateCLevel(isCallPool, cLevel64x64, oldLiquidity64x64, newLiquidity64x64);
  }

  /**
   * @notice TODO
   */
  function _update (
    PoolStorage.Layout storage l
  ) internal returns (int128 newPrice64x64, int128 newEmaVarianceAnnualized64x64) {
    if (l.updatedAt == block.timestamp) {
      return (l.getPriceUpdate(block.timestamp), l.emaVarianceAnnualized64x64);
    }

    newPrice64x64 = l.fetchPriceUpdate();

    uint256 updatedAt = l.updatedAt;

    int128 oldPrice64x64 = l.getPriceUpdate(updatedAt);

    if (l.getPriceUpdate(block.timestamp) == 0) {
      l.setPriceUpdate(newPrice64x64);
    }

    int128 logReturns64x64 = newPrice64x64.div(oldPrice64x64).ln();
    int128 oldEmaLogReturns64x64 = l.emaLogReturns64x64;
    int128 oldEmaVarianceAnnualized64x64 = l.emaVarianceAnnualized64x64;

    (int128 newEmaLogReturns64x64, int128 newEmaVariance64x64) = OptionMath.unevenRollingEmaVariance(
      oldEmaLogReturns64x64,
      oldEmaVarianceAnnualized64x64 / (365 * 24),
      logReturns64x64,
      updatedAt,
      block.timestamp
    );

    l.emaLogReturns64x64 = newEmaLogReturns64x64;
    newEmaVarianceAnnualized64x64 = newEmaVariance64x64 * (365 * 24);
    l.emaVarianceAnnualized64x64 = newEmaVarianceAnnualized64x64;

    emit UpdateVariance(
      oldEmaLogReturns64x64,
      oldEmaVarianceAnnualized64x64 / (365 * 24),
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

  function _mint (
    address account,
    uint256 tokenId,
    uint256 amount
  ) internal {
    // TODO: incorporate into SolidState
    _mint(account, tokenId, amount, '');
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

    PoolStorage.Layout storage l = PoolStorage.layout();

    for (uint256 i; i < ids.length; i++) {
      uint256 id = ids[i];

      if (id == UNDERLYING_FREE_LIQ_TOKEN_ID || id == BASE_FREE_LIQ_TOKEN_ID) {
        uint256 amount = amounts[i];

        if (amount > 0) {
          bool isCallPool = id == UNDERLYING_FREE_LIQ_TOKEN_ID;

          if (from != address(0)) {
            uint256 balance = balanceOf(from, id);
          // ToDo : Find better solution than checking if under 1e5 to ignore dust left ?
            if (balance > 1e5 && balance <= amount + 1e5) {
              require(balance - l.pendingDeposits[from][l.nextDeposits[isCallPool].eta][isCallPool] >= amount, 'Insuf balance');
              l.removeUnderwriter(from, isCallPool);
            }
          }

          if (to != address(0)) {
            uint256 balance = balanceOf(to, id);
            if (balance <= 1e5 && balance + amount > 1e5) {
              l.addUnderwriter(to, isCallPool);
            }
          }
        }
      }
    }
  }
}
