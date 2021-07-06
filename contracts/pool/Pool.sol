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
import { OptionMath } from '../libraries/OptionMath.sol';

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

  uint256 private immutable UNDERLYING_RESERVED_LIQ_TOKEN_ID;
  uint256 private immutable BASE_RESERVED_LIQ_TOKEN_ID;

  event Purchase (
    address indexed user,
    uint256 longTokenId,
    uint256 contractAmount,
    uint256 baseCost,
    uint256 feeCost,
    int128 spot64x64
  );

  event Exercise (
    address indexed user,
    uint256 longTokenId,
    uint256 contractAmount,
    uint256 exerciseValue
  );

  event Underwrite (
    address indexed underwriter,
    address indexed longReceiver,
    uint256 shortTokenId,
    uint256 intervalContractAmount,
    uint256 intervalPremium,
    bool isManualUnderwrite
  );

  event AssignExercise (
    address indexed underwriter,
    uint256 shortTokenId,
    uint256 freedAmount,
    uint256 intervalContractAmount
  );

  event Reassign (
    address indexed underwriter,
    uint256 shortTokenId,
    uint256 contractAmount,
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

  event FeeWithdrawal (
    bool indexed isCallPool,
    uint256 amount
  );

  event Annihilate (
    uint256 shortTokenId,
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

    UNDERLYING_RESERVED_LIQ_TOKEN_ID = PoolStorage.formatTokenId(PoolStorage.TokenType.UNDERLYING_RESERVED_LIQ, 0, 0);
    BASE_RESERVED_LIQ_TOKEN_ID = PoolStorage.formatTokenId(PoolStorage.TokenType.BASE_RESERVED_LIQ, 0, 0);
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
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @param contractAmount size of option contract
   * @param isCall true for call, false for put
   * @return baseCost64x64 64x64 fixed point representation of option cost denominated in underlying currency (without fee)
   * @return feeCost64x64 64x64 fixed point representation of option fee cost denominated in underlying currency for call, or base currency for put
   * @return cLevel64x64 64x64 fixed point representation of C-Level of Pool after purchase
   * @return slippageCoefficient64x64 64x64 fixed point representation of slippage coefficient for given order size
   */
  function quote (
    uint64 maturity,
    int128 strike64x64,
    uint256 contractAmount,
    bool isCall
  ) external view returns (
    int128 baseCost64x64,
    int128 feeCost64x64,
    int128 cLevel64x64,
    int128 slippageCoefficient64x64
  ) {
    (int128 spot64x64, , , , , int128 emaVarianceAnnualized64x64) = _calculateUpdate(PoolStorage.layout());

    (
      baseCost64x64,
      feeCost64x64,
      cLevel64x64,
      slippageCoefficient64x64
    ) = _quote(
      PoolStorage.QuoteArgsInternal(
        maturity,
        strike64x64,
        spot64x64,
        emaVarianceAnnualized64x64,
        contractAmount,
        isCall
      )
    );
  }

  /**
   * @notice set timestamp after which reinvestment is disabled
   * @param timestamp timestamp to begin divestment
   */
  function setDivestmentTimestamp (
    uint64 timestamp
  ) external {
    PoolStorage.Layout storage l = PoolStorage.layout();
    l.divestmentTimestamps[msg.sender] = timestamp;
  }

  /**
   * @notice purchase call option
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @param contractAmount size of option contract
   * @param isCall true for call, false for put,
   * @param maxCost maximum acceptable cost after accounting for slippage
   * @return baseCost quantity of tokens required to purchase long position
   * @return feeCost quantity of tokens required to pay fees
   */
  function purchase (
    uint64 maturity,
    int128 strike64x64,
    uint256 contractAmount,
    bool isCall,
    uint256 maxCost
  ) external payable returns (uint256 baseCost, uint256 feeCost) {
    // TODO: specify payment currency

    PoolStorage.Layout storage l = PoolStorage.layout();

    require(maturity >= block.timestamp + (1 days), 'exp < 1 day');
    require(maturity < block.timestamp + (29 days), 'exp > 28 days');
    require(maturity % (1 days) == 0, 'exp not end UTC day');

    (int128 newPrice64x64,) = _update(l);

    require(strike64x64 <= newPrice64x64 * 3 / 2, 'strike > 1.5x spot');
    require(strike64x64 >= newPrice64x64 * 3 / 4, 'strike < 0.75x spot');

    {
      uint256 size = isCall
        ? contractAmount
        : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(contractAmount));

      require(size <= totalSupply(_getFreeLiquidityTokenId(isCall)) - l.nextDeposits[isCall].totalPendingDeposits, 'insuf liq');
    }

    int128 cLevel64x64;

    {
      int128 baseCost64x64;
      int128 feeCost64x64;

      (baseCost64x64, feeCost64x64, cLevel64x64,) = _quote(
        PoolStorage.QuoteArgsInternal(
          maturity,
          strike64x64,
          newPrice64x64,
          l.emaVarianceAnnualized64x64,
          contractAmount,
          isCall
        )
      );

      baseCost = ABDKMath64x64Token.toDecimals(baseCost64x64, l.getTokenDecimals(isCall));
      feeCost = ABDKMath64x64Token.toDecimals(feeCost64x64, l.getTokenDecimals(isCall));
    }

    require(baseCost + feeCost <= maxCost, 'excess slipp');
    _pullFrom(msg.sender, _getPoolToken(isCall), baseCost + feeCost);

    uint256 longTokenId = PoolStorage.formatTokenId(_getTokenType(isCall, true), maturity, strike64x64);
    uint256 shortTokenId = PoolStorage.formatTokenId(_getTokenType(isCall, false), maturity, strike64x64);

    // mint long option token for buyer
    _mint(msg.sender, longTokenId, contractAmount);

    int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);
    // burn free liquidity tokens from other underwriters
    _mintShortTokenLoop(l, contractAmount, baseCost, shortTokenId, isCall);
    int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

    _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCall);

    // mint reserved liquidity tokens for fee receiver
    _mint(FEE_RECEIVER_ADDRESS, _getReservedLiquidityTokenId(isCall), feeCost);

    emit Purchase(
      msg.sender,
      longTokenId,
      contractAmount,
      baseCost,
      feeCost,
      newPrice64x64
    );
  }

  /**
   * @notice exercise call option on behalf of holder
   * @param holder owner of long option tokens to exercise
   * @param longTokenId long option token id
   * @param contractAmount quantity of tokens to exercise
   */
  function exerciseFrom (
    address holder,
    uint256 longTokenId,
    uint256 contractAmount
  ) external {
    if (msg.sender != holder) {
      require(isApprovedForAll(holder, msg.sender), "not approved");
    }

    _exercise(holder, longTokenId, contractAmount);
  }

  /**
   * @notice process expired option, freeing liquidity and distributing profits
   * @param longTokenId long option token id
   * @param contractAmount quantity of tokens to process
   */
  function processExpired (
    uint256 longTokenId,
    uint256 contractAmount
  ) external {
    _exercise(address(0), longTokenId, contractAmount);
  }

  /**
   * @notice write call option without using liquidity from the pool on behalf of another address
   * @param underwriter underwriter of the option from who collateral will be deposited
   * @param longReceiver address who will receive the long token (Can be the underwriter)
   * @param maturity timestamp of option maturity
   * @param strike64x64 64x64 fixed point representation of strike price
   * @param contractAmount quantity of option contract tokens to exercise
   * @param isCall whether this is a call or a put
   * @return longTokenId token id of the long call
   * @return shortTokenId token id of the short call
   */
  function writeFrom (
    address underwriter,
    address longReceiver,
    uint64 maturity,
    int128 strike64x64,
    uint256 contractAmount,
    bool isCall
  ) external payable returns(uint256 longTokenId, uint256 shortTokenId) {
    require(msg.sender == underwriter || isApprovedForAll(underwriter, msg.sender), 'not approved');

    address token = _getPoolToken(isCall);
    uint256 fee = FEE_64x64.mulu(contractAmount);

    uint256 tokenAmount = isCall ? (contractAmount + fee) : PoolStorage.layout().fromUnderlyingToBaseDecimals(strike64x64.mulu(contractAmount + fee));

    _pullFrom(underwriter, token, tokenAmount);
    // mint reserved liquidity tokens for fee receiver
    _mint(FEE_RECEIVER_ADDRESS, _getReservedLiquidityTokenId(isCall), fee);

    longTokenId = PoolStorage.formatTokenId(_getTokenType(isCall, true), maturity, strike64x64);
    shortTokenId = PoolStorage.formatTokenId(_getTokenType(isCall, false), maturity, strike64x64);

    // mint long option token for underwriter (ERC1155)
    _mint(longReceiver, longTokenId, contractAmount, '');
    // mint short option token for underwriter (ERC1155)
    _mint(underwriter, shortTokenId, contractAmount, '');

    emit Underwrite(underwriter, longReceiver, shortTokenId, contractAmount, 0, true);
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
    _pullFrom(msg.sender, _getPoolToken(isCallPool), amount);

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
    uint256 toWithdraw = amount;

    _processPendingDeposits(l, isCallPool);

    uint256 depositedAt = l.depositedAt[msg.sender][isCallPool];

    require(depositedAt + (1 days) < block.timestamp, 'liq lock 1d');

    int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCallPool);

    {
      uint256 reservedLiqTokenId = _getReservedLiquidityTokenId(isCallPool);
      uint256 reservedLiquidity = ERC1155EnumerableStorage.layout().totalSupply[reservedLiqTokenId];

      if (reservedLiquidity > 0) {
        uint256 reservedLiqToWithdraw;
        if (reservedLiquidity < toWithdraw) {
          reservedLiqToWithdraw = reservedLiquidity;
        } else {
          reservedLiqToWithdraw = toWithdraw;
        }

        toWithdraw -= reservedLiqToWithdraw;
        // burn reserved liquidity tokens from sender
        _burn(msg.sender, reservedLiqTokenId, reservedLiqToWithdraw);
      }
    }

    if (toWithdraw > 0) {
      // burn free liquidity tokens from sender
      _burn(msg.sender, _getFreeLiquidityTokenId(isCallPool), toWithdraw);

      int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCallPool);
      _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCallPool);
    }

    _pushTo(msg.sender, _getPoolToken(isCallPool), amount);
    emit Withdrawal(msg.sender, isCallPool, depositedAt, amount);
  }


  /**
   * @notice reassign short position to new liquidity provider
   * @param shortTokenId ERC1155 short token id
   * @param contractAmount quantity of option contract tokens to reassign
   * @return baseCost quantity of tokens required to reassign short position
   * @return feeCost quantity of tokens required to pay fees
   */
  function reassign (
    uint256 shortTokenId,
    uint256 contractAmount
  ) external returns (uint256 baseCost, uint256 feeCost) {
    PoolStorage.Layout storage l = PoolStorage.layout();
    (int128 newPrice64x64, ) = _update(l);
    (baseCost, feeCost) = _reassign(l, shortTokenId, contractAmount, newPrice64x64);
  }

  /**
   * @notice TODO
   */
  function reassignBatch (
    uint256[] calldata ids,
    uint256[] calldata contractAmounts
  ) public returns (uint256[] memory baseCosts, uint256[] memory feeCosts) {
    require(ids.length == contractAmounts.length, 'TODO');

    PoolStorage.Layout storage l = PoolStorage.layout();

    (int128 newPrice64x64, ) = _update(l);

    baseCosts = new uint256[](ids.length);
    feeCosts = new uint256[](ids.length);

    for (uint256 i; i < ids.length; i++) {
      (baseCosts[i], feeCosts[i]) = _reassign(l, ids[i], contractAmounts[i], newPrice64x64);
    }
  }

  /**
   * @notice TODO
   */
  function withdrawAllAndReassignBatch (
    bool isCallPool,
    uint256[] calldata ids,
    uint256[] calldata contractAmounts
  ) external returns (uint256[] memory baseCosts, uint256[] memory feeCosts) {
    uint256 balance = balanceOf(msg.sender, _getFreeLiquidityTokenId(isCallPool));

    if (balance > 0) {
      withdraw(balance, isCallPool);
    }

    (baseCosts, feeCosts) = reassignBatch(ids, contractAmounts);
  }

  /**
   * @notice Update pool data
   */
  function update () external returns (int128 newEmaVarianceAnnualized64x64) {
    (,newEmaVarianceAnnualized64x64) = _update(PoolStorage.layout());
  }

  /**
   * @notice TODO
   */
  function withdrawFees () external  {
    _withdrawFees(true);
    _withdrawFees(false);
  }

  /**
   * @notice Burn long and short tokens to withdraw collateral
   * @param shortTokenId ERC1155 short token id
   * @param contractAmount quantity of option contract tokens to annihilate
   */
  function annihilate (
    uint256 shortTokenId,
    uint256 contractAmount
  ) external {
    (PoolStorage.TokenType tokenType, uint64 maturity, int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);
    require(tokenType == PoolStorage.TokenType.SHORT_CALL || tokenType == PoolStorage.TokenType.SHORT_PUT, "not short");
    bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL;
    uint256 longTokenId = PoolStorage.formatTokenId(_getTokenType(isCall, true), maturity, strike64x64);

    _burn(msg.sender, shortTokenId, contractAmount);
    _burn(msg.sender, longTokenId, contractAmount);

    _pushTo(
      msg.sender,
      _getPoolToken(isCall),
      isCall ? contractAmount : PoolStorage.layout().fromUnderlyingToBaseDecimals(strike64x64.mulu(contractAmount))
    );

    emit Annihilate(shortTokenId, contractAmount);
  }

  ////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////

  //////////////
  // Internal //
  //////////////

  function _withdrawFees (bool isCall) internal {
    uint256 tokenId = _getReservedLiquidityTokenId(isCall);
    uint256 balance = balanceOf(FEE_RECEIVER_ADDRESS, tokenId);
    if (balance > 0) {
      _burn(FEE_RECEIVER_ADDRESS, tokenId, balance);
      _pushTo(FEE_RECEIVER_ADDRESS, _getPoolToken(isCall), balance);

      emit FeeWithdrawal(isCall, balance);
    }
  }

  /**
   * @notice TODO
   */
  function _quote (
    PoolStorage.QuoteArgsInternal memory args
  ) internal view returns (
    int128 baseCost64x64,
    int128 feeCost64x64,
    int128 cLevel64x64,
    int128 slippageCoefficient64x64
  ) {
    PoolStorage.Layout storage l = PoolStorage.layout();

    int128 contractAmount64x64 = ABDKMath64x64Token.fromDecimals(args.contractAmount, l.underlyingDecimals);
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
        oldLiquidity64x64.sub(contractAmount64x64),
        0x10000000000000000, // 64x64 fixed point representation of 1
        isCall
      )
    );

    baseCost64x64 = isCall ? price64x64.mul(contractAmount64x64).div(args.spot64x64) : price64x64.mul(contractAmount64x64);
    feeCost64x64 = baseCost64x64.mul(FEE_64x64);
  }

  /**
   * @notice TODO
   */
  function _exercise (
    address holder, // holder address of option contract tokens to exercise
    uint256 longTokenId, // amount quantity of option contract tokens to exercise
    uint256 contractAmount // quantity of option contract tokens to exercise
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

    (int128 spot64x64,) = _update(l);

    if (maturity < block.timestamp) {
      spot64x64 = l.getPriceUpdateAfter(maturity);
    }

    require(onlyExpired || (isCall ? (spot64x64 > strike64x64) : (spot64x64 < strike64x64)), 'not ITM');

    uint256 exerciseValue;
    // option has a non-zero exercise value
    if (isCall) {
      if (spot64x64 > strike64x64) {
        exerciseValue = spot64x64.sub(strike64x64).div(spot64x64).mulu(contractAmount);
      }
    } else {
      if (spot64x64 < strike64x64) {
        exerciseValue = l.fromUnderlyingToBaseDecimals(strike64x64.sub(spot64x64).mulu(contractAmount));
      }
    }

    if (onlyExpired) {
      _burnLongTokenLoop(
        contractAmount,
        exerciseValue,
        longTokenId,
        isCall
      );
    } else {
      // burn long option tokens from sender
      _burn(holder, longTokenId, contractAmount);

      if (exerciseValue > 0) {
        _pushTo(holder, _getPoolToken(isCall), exerciseValue);

        emit Exercise(
          holder,
          longTokenId,
          contractAmount,
          exerciseValue
        );
      }
    }

    _burnShortTokenLoop(
      contractAmount,
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
    uint256 contractAmount,
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
        PoolStorage.QuoteArgsInternal(
          maturity,
          strike64x64,
          newPrice64x64,
          l.emaVarianceAnnualized64x64,
          contractAmount,
          isCall
        )
      );

      baseCost = ABDKMath64x64Token.toDecimals(baseCost64x64, l.getTokenDecimals(isCall));
      feeCost = ABDKMath64x64Token.toDecimals(feeCost64x64, l.getTokenDecimals(isCall));

      uint256 pushAmount = isCall ? contractAmount : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(contractAmount));

      _pushTo(
        msg.sender,
        _getPoolToken(isCall),
        pushAmount - baseCost - feeCost
      );
    }

    // burn short option tokens from underwriter
    _burn(msg.sender, shortTokenId, contractAmount);

    int128 oldLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);
    // burn free liquidity tokens from other underwriters
    _mintShortTokenLoop(l, contractAmount, baseCost, shortTokenId, isCall);
    int128 newLiquidity64x64 = l.totalFreeLiquiditySupply64x64(isCall);

    _setCLevel(l, oldLiquidity64x64, newLiquidity64x64, isCall);

    // mint reserved liquidity tokens for fee receiver
    _mint(FEE_RECEIVER_ADDRESS, _getReservedLiquidityTokenId(isCall), feeCost);

    emit Reassign(
      msg.sender,
      shortTokenId,
      contractAmount,
      baseCost,
      feeCost,
      cLevel64x64,
      newPrice64x64
    );
  }

  function _mintShortTokenLoop (
    PoolStorage.Layout storage l,
    uint256 contractAmount,
    uint256 premium,
    uint256 shortTokenId,
    bool isCall
  ) private {
    address underwriter;
    uint256 freeLiqTokenId = _getFreeLiquidityTokenId(isCall);
    (, , int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);

    uint256 toPay = isCall ? contractAmount : l.fromUnderlyingToBaseDecimals(strike64x64.mulu(contractAmount));

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

      if (!l.getReinvestmentStatus(underwriter)) {
        _burn(underwriter, freeLiqTokenId, balance);
        _mint(underwriter, _getReservedLiquidityTokenId(isCall), balance, '');
        continue;
      }

      // amount of liquidity provided by underwriter, accounting for reinvested premium
      uint256 intervalContractAmount = (balance - l.pendingDeposits[underwriter][l.nextDeposits[isCall].eta][isCall]) * (toPay + premium) / toPay;
      if (intervalContractAmount == 0) continue;
      if (intervalContractAmount > toPay) intervalContractAmount = toPay;

      // amount of premium paid to underwriter
      uint256 intervalPremium = premium * intervalContractAmount / toPay;
      premium -= intervalPremium;
      toPay -= intervalContractAmount;

      // burn free liquidity tokens from underwriter
      _burn(underwriter, freeLiqTokenId, intervalContractAmount - intervalPremium);

      if (isCall == false) {
        // For PUT, conversion to contract amount is done here (Prior to this line, it is token amount)
        intervalContractAmount = l.fromBaseToUnderlyingDecimals(strike64x64.inv().mulu(intervalContractAmount));
      }

      // mint short option tokens for underwriter
      // toPay == 0 ? contractAmount : intervalContractAmount : To prevent minting less than amount,
      // because of rounding (Can happen for put, because of fixed point precision)
      _mint(underwriter, shortTokenId, toPay == 0 ? contractAmount : intervalContractAmount);

      emit Underwrite(underwriter, msg.sender, shortTokenId, toPay == 0 ? contractAmount : intervalContractAmount, intervalPremium, false);

      contractAmount -= intervalContractAmount;
    }
  }

  function _burnLongTokenLoop (
    uint256 contractAmount,
    uint256 exerciseValue,
    uint256 longTokenId,
    bool isCall
  ) internal {
    EnumerableSet.AddressSet storage holders = ERC1155EnumerableStorage.layout().accountsByToken[longTokenId];

    while (contractAmount > 0) {
      address longTokenHolder = holders.at(holders.length() - 1);

      uint256 intervalContractAmount = balanceOf(longTokenHolder, longTokenId);
      if (intervalContractAmount > contractAmount) intervalContractAmount = contractAmount;

      uint256 intervalExerciseValue;

      if (exerciseValue > 0) {
        intervalExerciseValue = exerciseValue * intervalContractAmount / contractAmount;
        exerciseValue -= intervalExerciseValue;
        _pushTo(longTokenHolder, _getPoolToken(isCall), intervalExerciseValue);
      }

      contractAmount -= intervalContractAmount;

      emit Exercise (
        longTokenHolder,
        longTokenId,
        intervalContractAmount,
        intervalExerciseValue
      );

      _burn(longTokenHolder, longTokenId, intervalContractAmount);
    }
  }

  function _burnShortTokenLoop (
    uint256 contractAmount,
    uint256 exerciseValue,
    uint256 shortTokenId,
    bool isCall
  ) private {
    EnumerableSet.AddressSet storage underwriters = ERC1155EnumerableStorage.layout().accountsByToken[shortTokenId];
    (, , int128 strike64x64) = PoolStorage.parseTokenId(shortTokenId);

    while (contractAmount > 0) {
      address underwriter = underwriters.at(underwriters.length() - 1);

      // amount of liquidity provided by underwriter
      uint256 intervalContractAmount = balanceOf(underwriter, shortTokenId);
      if (intervalContractAmount > contractAmount) intervalContractAmount = contractAmount;

      // amount of value claimed by buyer
      uint256 intervalExerciseValue = exerciseValue * intervalContractAmount / contractAmount;
      exerciseValue -= intervalExerciseValue;
      contractAmount -= intervalContractAmount;

      uint256 freeLiq = isCall
        ? intervalContractAmount - intervalExerciseValue
        : PoolStorage.layout().fromUnderlyingToBaseDecimals(strike64x64.mulu(intervalContractAmount)) - intervalExerciseValue;

      // mint free liquidity tokens for underwriter
      if (PoolStorage.layout().getReinvestmentStatus(underwriter)) {
        _addToDepositQueue(underwriter, freeLiq, isCall);
      } else {
        _mint(underwriter, _getReservedLiquidityTokenId(isCall), freeLiq, '');
      }
      // burn short option tokens from underwriter
      _burn(underwriter, shortTokenId, intervalContractAmount);

      emit AssignExercise(underwriter, shortTokenId, freeLiq, intervalContractAmount);
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

  function _getReservedLiquidityTokenId (
    bool isCall
  ) internal view returns (uint256 reservedLiqTokenId) {
    reservedLiqTokenId = isCall ? UNDERLYING_RESERVED_LIQ_TOKEN_ID : BASE_RESERVED_LIQ_TOKEN_ID;
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
  ) internal returns (
    int128 newPrice64x64,
    int128 newEmaVarianceAnnualized64x64
  ) {
    uint256 updatedAt = l.updatedAt;

    if (l.updatedAt == block.timestamp) {
      return (l.getPriceUpdate(block.timestamp), l.emaVarianceAnnualized64x64);
    }

    int128 logReturns64x64;
    int128 oldEmaLogReturns64x64;
    int128 newEmaLogReturns64x64;
    int128 oldEmaVarianceAnnualized64x64;

    (
      newPrice64x64,
      logReturns64x64,
      oldEmaLogReturns64x64,
      newEmaLogReturns64x64,
      oldEmaVarianceAnnualized64x64,
      newEmaVarianceAnnualized64x64
    ) = _calculateUpdate(l);

    if (l.getPriceUpdate(block.timestamp) == 0) {
      l.setPriceUpdate(newPrice64x64);
    }

    l.emaLogReturns64x64 = newEmaLogReturns64x64;
    l.emaVarianceAnnualized64x64 = newEmaVarianceAnnualized64x64;
    l.updatedAt = block.timestamp;

    _processPendingDeposits(l, true);
    _processPendingDeposits(l, false);

    emit UpdateVariance(
      oldEmaLogReturns64x64,
      oldEmaVarianceAnnualized64x64 / (365 * 24),
      logReturns64x64,
      updatedAt,
      newEmaVarianceAnnualized64x64
    );
  }

  /**
   * @notice TODO
   */
  function _calculateUpdate (
    PoolStorage.Layout storage l
  ) internal view returns (
    int128 newPrice64x64,
    int128 logReturns64x64,
    int128 oldEmaLogReturns64x64,
    int128 newEmaLogReturns64x64,
    int128 oldEmaVarianceAnnualized64x64,
    int128 newEmaVarianceAnnualized64x64
  ) {
    uint256 updatedAt = l.updatedAt;
    int128 oldPrice64x64 = l.getPriceUpdate(updatedAt);
    newPrice64x64 = l.fetchPriceUpdate();

    logReturns64x64 = newPrice64x64.div(oldPrice64x64).ln();
    oldEmaLogReturns64x64 = l.emaLogReturns64x64;
    oldEmaVarianceAnnualized64x64 = l.emaVarianceAnnualized64x64;

    int128 newEmaVariance64x64;

    (newEmaLogReturns64x64, newEmaVariance64x64) = OptionMath.unevenRollingEmaVariance(
      oldEmaLogReturns64x64,
      oldEmaVarianceAnnualized64x64 / (365 * 24),
      logReturns64x64,
      updatedAt,
      block.timestamp
    );

    newEmaVarianceAnnualized64x64 = newEmaVariance64x64 * (365 * 24);
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
   * @param from address from which tokens are pulled from
   * @param token ERC20 token address
   * @param amount quantity of token to transfer
   */
  function _pullFrom (
    address from,
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
        IERC20(token).transferFrom(from, address(this), amount),
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
