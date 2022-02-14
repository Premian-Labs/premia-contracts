import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  FeeDiscount,
  FeeDiscount__factory,
  IPool,
  PoolMock,
  PoolMock__factory,
  Proxy__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';

import { describeBehaviorOfPoolBase } from '../../spec/pool/PoolBase.behavior';
import { describeBehaviorOfPoolExercise } from '../../spec/pool/PoolExercise.behavior';
import { describeBehaviorOfPoolIO } from '../../spec/pool/PoolIO.behavior';
import { describeBehaviorOfPoolSettings } from '../../spec/pool/PoolSettings.behavior';
import { describeBehaviorOfPoolView } from '../../spec/pool/PoolView.behavior';
import { describeBehaviorOfPoolWrite } from '../../spec/pool/PoolWrite.behavior';
import chai, { expect } from 'chai';
import { increaseTimestamp } from '../utils/evm';
import { parseUnits } from 'ethers/lib/utils';
import {
  formatOption,
  formatOptionToNb,
  getExerciseValue,
  parseOption,
  parseUnderlying,
  getFreeLiqTokenId,
  getReservedLiqTokenId,
  getStrike,
  getMaturity,
  getMaxCost,
  PoolUtil,
} from './PoolUtil';
import chaiAlmost from 'chai-almost';
import { BigNumber } from 'ethers';
import { describeBehaviorOfProxy } from '@solidstate/spec';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
  TokenType,
} from '@premia/utils';
import { createUniswap, IUniswap } from '../utils/uniswap';

chai.use(chaiAlmost(0.02));

const oneMonth = 30 * 24 * 3600;

describe('PoolProxy', function () {
  let owner: SignerWithAddress;
  let lp1: SignerWithAddress;
  let lp2: SignerWithAddress;
  let buyer: SignerWithAddress;
  let thirdParty: SignerWithAddress;
  let feeReceiver: SignerWithAddress;
  let uniswap: IUniswap;

  let xPremia: ERC20Mock;
  let feeDiscount: FeeDiscount;

  let pool: IPool;
  let instance: IPool;
  let poolMock: PoolMock;
  let poolWeth: IPool;
  let p: PoolUtil;
  let premia: ERC20Mock;

  const underlyingFreeLiqToken = formatTokenId({
    tokenType: TokenType.UnderlyingFreeLiq,
    maturity: BigNumber.from(0),
    strike64x64: BigNumber.from(0),
  });
  const baseFreeLiqToken = formatTokenId({
    tokenType: TokenType.BaseFreeLiq,
    maturity: BigNumber.from(0),
    strike64x64: BigNumber.from(0),
  });

  const spotPrice = 2000;

  before(async function () {
    [owner, lp1, lp2, buyer, thirdParty, feeReceiver] =
      await ethers.getSigners();
  });

  beforeEach(async function () {
    const erc20Factory = new ERC20Mock__factory(owner);

    premia = await erc20Factory.deploy('PREMIA', 18);
    xPremia = await erc20Factory.deploy('xPREMIA', 18);

    const feeDiscountImpl = await new FeeDiscount__factory(owner).deploy(
      xPremia.address,
    );
    const feeDiscountProxy = await new ProxyUpgradeableOwnable__factory(
      owner,
    ).deploy(feeDiscountImpl.address);
    feeDiscount = FeeDiscount__factory.connect(feeDiscountProxy.address, owner);

    uniswap = await createUniswap(owner);

    p = await PoolUtil.deploy(
      owner,
      premia.address,
      spotPrice,
      feeReceiver,
      feeDiscount.address,
      uniswap.factory.address,
      uniswap.weth.address,
    );

    pool = p.pool;
    poolMock = PoolMock__factory.connect(p.pool.address, owner);
    poolWeth = p.poolWeth;

    instance = p.pool;
  });

  describeBehaviorOfProxy({
    deploy: async () => Proxy__factory.connect(p.pool.address, owner),
    implementationFunction: 'getPoolSettings()',
    implementationFunctionArgs: [],
  });

  describeBehaviorOfPoolBase(
    {
      deploy: async () => instance,
      getUnderlying: async () => p.underlying,
      getBase: async () => p.base,
      getPoolUtil: async () => p,
      // mintERC1155: (recipient, tokenId, amount) =>
      //   instance['mint(address,uint256,uint256)'](recipient, tokenId, amount),
      // burnERC1155: (recipient, tokenId, amount) =>
      //   instance['burn(address,uint256,uint256)'](recipient, tokenId, amount),
      mintERC1155: undefined as any,
      burnERC1155: undefined as any,
    },
    // TODO: don't skip
    ['::ERC1155Enumerable'],
  );

  describeBehaviorOfPoolExercise({
    deploy: async () => instance,
    getBase: async () => p.base,
    getUnderlying: async () => p.underlying,
    getFeeDiscount: async () => feeDiscount,
    getXPremia: async () => xPremia,
    getPoolUtil: async () => p,
  });

  describeBehaviorOfPoolIO({
    deploy: async () => instance,
    getBase: async () => p.base,
    getUnderlying: async () => p.underlying,
    getPoolUtil: async () => p,
    getUniswap: async () => uniswap,
  });

  describeBehaviorOfPoolSettings({
    deploy: async () => instance,
    getProtocolOwner: async () => owner,
    getNonProtocolOwner: async () => thirdParty,
  });

  describeBehaviorOfPoolView({
    deploy: async () => instance,
    getPoolUtil: async () => p,
  });

  describeBehaviorOfPoolWrite({
    deploy: async () => instance,
    getBase: async () => p.base,
    getUnderlying: async () => p.underlying,
    getPoolUtil: async () => p,
    getUniswap: async () => uniswap,
  });

  describe('user TVL', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should not decrease user TVL if liquidity is used to underwrite option', async () => {
          const amountNb = isCall ? 10 : 100000;
          const amount = parseOption(amountNb.toString(), isCall);
          await p.depositLiquidity(lp1, amount, isCall);

          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, spotPrice));

          const purchaseAmountNb = 4;
          const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

          const quote = await pool.quote(
            buyer.address,
            maturity,
            strike64x64,
            purchaseAmount,
            isCall,
          );

          const mintAmount = parseOption('10000', isCall);
          await p.getToken(isCall).mint(buyer.address, mintAmount);
          await p
            .getToken(isCall)
            .connect(buyer)
            .approve(pool.address, ethers.constants.MaxUint256);

          await pool
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
              getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
            );

          expect(
            Number(
              formatOption(
                await p.pool.balanceOf(lp1.address, getFreeLiqTokenId(isCall)),
                isCall,
              ),
            ),
          ).to.almost(
            amountNb -
              (isCall
                ? purchaseAmountNb
                : purchaseAmountNb * getStrike(isCall, spotPrice)) +
              fixedToNumber(quote.baseCost64x64),
          );

          const userTVL = await p.pool.getUserTVL(lp1.address);
          const totalTVL = await p.pool.getTotalTVL();
          const baseCost = fixedToNumber(quote.baseCost64x64);

          expect(formatOptionToNb(userTVL.underlyingTVL, isCall)).to.almost(
            isCall ? amountNb + baseCost : 0,
          );
          expect(formatOptionToNb(userTVL.baseTVL, isCall)).to.almost(
            isCall ? 0 : amountNb + baseCost,
          );
          expect(formatOptionToNb(totalTVL.underlyingTVL, isCall)).to.almost(
            isCall ? amountNb + baseCost : 0,
          );
          expect(formatOptionToNb(totalTVL.baseTVL, isCall)).to.almost(
            isCall ? 0 : amountNb + baseCost,
          );
        });

        it('should decrease user TVL when free liquidity is moved as reserved liquidity and not decrease user TVL when withdrawing reserved liquidity', async () => {
          const amountNb = isCall ? 10 : 100000;
          const amount = parseOption(amountNb.toString(), isCall);
          await p.depositLiquidity(lp1, amount, isCall);
          await p.depositLiquidity(lp2, amount, isCall);

          const { timestamp } = await ethers.provider.getBlock('latest');

          await p.pool
            .connect(lp1)
            .setDivestmentTimestamp(timestamp + 25 * 3600, isCall);
          await increaseTimestamp(26 * 3600);

          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, spotPrice));

          const purchaseAmountNb = 4;
          const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

          const quote = await pool.quote(
            buyer.address,
            maturity,
            strike64x64,
            purchaseAmount,
            isCall,
          );

          const mintAmount = parseOption('10000', isCall);
          await p.getToken(isCall).mint(buyer.address, mintAmount);
          await p
            .getToken(isCall)
            .connect(buyer)
            .approve(pool.address, ethers.constants.MaxUint256);

          await pool
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
              getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
            );

          let lp1TVL = await p.pool.getUserTVL(lp1.address);
          const lp2TVL = await p.pool.getUserTVL(lp2.address);
          const totalTVL = await p.pool.getTotalTVL();
          const baseCost = fixedToNumber(quote.baseCost64x64);

          expect(
            await p.pool.balanceOf(lp1.address, getFreeLiqTokenId(isCall)),
          ).to.eq(0);
          expect(
            await p.pool.balanceOf(lp1.address, getReservedLiqTokenId(isCall)),
          ).to.eq(amount);

          expect(lp1TVL.underlyingTVL).to.eq(0);
          expect(lp1TVL.baseTVL).to.eq(0);
          expect(formatOptionToNb(lp2TVL.underlyingTVL, isCall)).to.almost(
            isCall ? amountNb + baseCost : 0,
          );
          expect(formatOptionToNb(lp2TVL.baseTVL, isCall)).to.almost(
            isCall ? 0 : amountNb + baseCost,
          );
          expect(formatOptionToNb(totalTVL.underlyingTVL, isCall)).to.almost(
            isCall ? amountNb + baseCost : 0,
          );
          expect(formatOptionToNb(totalTVL.baseTVL, isCall)).to.almost(
            isCall ? 0 : amountNb + baseCost,
          );

          await p.depositLiquidity(lp1, amount.div(2), isCall);
          await increaseTimestamp(25 * 3600);

          await p.pool.connect(lp1).withdraw(amount, isCall);

          lp1TVL = await p.pool.getUserTVL(lp1.address);

          expect(
            await p.pool.balanceOf(lp1.address, getReservedLiqTokenId(isCall)),
          ).to.eq(0);

          expect(lp1TVL.underlyingTVL).to.eq(isCall ? amount.div(2) : 0);
          expect(lp1TVL.baseTVL).to.eq(isCall ? 0 : amount.div(2));
        });
      });
    }
  });
});
