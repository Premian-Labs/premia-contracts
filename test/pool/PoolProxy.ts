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
import { increaseTimestamp, setTimestamp } from '../utils/evm';
import { hexlify, hexZeroPad, parseEther, parseUnits } from 'ethers/lib/utils';
import {
  DECIMALS_BASE,
  DECIMALS_UNDERLYING,
  FEE,
  formatOption,
  formatOptionToNb,
  formatUnderlying,
  getExerciseValue,
  getTokenDecimals,
  parseBase,
  parseOption,
  parseUnderlying,
  PoolUtil,
} from './PoolUtil';
import { bnToNumber } from '../utils/math';
import chaiAlmost from 'chai-almost';
import { BigNumber } from 'ethers';
import { ZERO_ADDRESS } from '../utils/constants';
import { describeBehaviorOfProxy } from '@solidstate/spec';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
  TokenType,
} from '@premia/utils';
import {
  createUniswap,
  createUniswapPair,
  depositUniswapLiquidity,
  IUniswap,
} from '../utils/uniswap';

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

  const getStrike = (isCall: boolean) => {
    return p.getStrike(isCall, spotPrice);
  };

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
      getPoolUtil: async () => p,
      // mintERC1155: (recipient, tokenId, amount) =>
      //   instance['mint(address,uint256,uint256)'](recipient, tokenId, amount),
      // burnERC1155: (recipient, tokenId, amount) =>
      //   instance['burn(address,uint256,uint256)'](recipient, tokenId, amount),
      mintERC1155: undefined as any,
      burnERC1155: undefined as any,
    },
    ['::ERC1155Enumerable'],
  );

  describeBehaviorOfPoolExercise({
    deploy: async () => instance,
    getFeeDiscount: async () => feeDiscount,
    getXPremia: async () => xPremia,
    getPoolUtil: async () => p,
  });

  describeBehaviorOfPoolIO({
    deploy: async () => instance,
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
    getPoolUtil: async () => p,
    getUniswap: async () => uniswap,
  });

  describe('user TVL', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should increase user TVL on deposit', async () => {
          const amount = parseOption('10', isCall);
          const amount2 = parseOption('5', isCall);
          await p.depositLiquidity(lp1, amount, isCall);
          await p.depositLiquidity(lp2, amount2, isCall);

          const userTVL = await p.pool.getUserTVL(lp1.address);
          const totalTVL = await p.pool.getTotalTVL();

          expect(userTVL.underlyingTVL).to.eq(isCall ? amount : 0);
          expect(userTVL.baseTVL).to.eq(isCall ? 0 : amount);
          expect(totalTVL.underlyingTVL).to.eq(
            isCall ? amount.add(amount2) : 0,
          );
          expect(totalTVL.baseTVL).to.eq(isCall ? 0 : amount.add(amount2));
        });

        it('should decrease user TVL on withdrawal', async () => {
          const amount = parseOption('10', isCall);
          await p.depositLiquidity(lp1, amount, isCall);

          await increaseTimestamp(25 * 3600);

          await p.pool.connect(lp1).withdraw(parseOption('3', isCall), isCall);

          const userTVL = await p.pool.getUserTVL(lp1.address);
          const totalTVL = await p.pool.getTotalTVL();

          const amountLeft = parseOption('7', isCall);

          expect(userTVL.underlyingTVL).to.eq(isCall ? amountLeft : 0);
          expect(userTVL.baseTVL).to.eq(isCall ? 0 : amountLeft);
          expect(totalTVL.underlyingTVL).to.eq(isCall ? amountLeft : 0);
          expect(totalTVL.baseTVL).to.eq(isCall ? 0 : amountLeft);
        });

        it('should not decrease user TVL if liquidity is used to underwrite option', async () => {
          const amountNb = isCall ? 10 : 100000;
          const amount = parseOption(amountNb.toString(), isCall);
          await p.depositLiquidity(lp1, amount, isCall);

          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

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
              p.getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
            );

          expect(
            Number(
              formatOption(
                await p.pool.balanceOf(
                  lp1.address,
                  p.getFreeLiqTokenId(isCall),
                ),
                isCall,
              ),
            ),
          ).to.almost(
            amountNb -
              (isCall
                ? purchaseAmountNb
                : purchaseAmountNb * getStrike(isCall)) +
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

        it('should transfer user TVL if free liq token is transferred', async () => {
          const amount = parseOption('10', isCall);
          const amountToTransfer = parseOption('3', isCall);
          await p.depositLiquidity(lp1, amount, isCall);
          await increaseTimestamp(25 * 3600);
          await p.pool
            .connect(lp1)
            .safeTransferFrom(
              lp1.address,
              lp2.address,
              p.getFreeLiqTokenId(isCall),
              amountToTransfer,
              '0x',
            );

          const lp1TVL = await p.pool.getUserTVL(lp1.address);
          const lp2TVL = await p.pool.getUserTVL(lp2.address);
          const totalTVL = await p.pool.getTotalTVL();

          expect(lp1TVL.underlyingTVL).to.eq(
            isCall ? amount.sub(amountToTransfer) : 0,
          );
          expect(lp1TVL.baseTVL).to.eq(
            isCall ? 0 : amount.sub(amountToTransfer),
          );
          expect(lp2TVL.underlyingTVL).to.eq(isCall ? amountToTransfer : 0);
          expect(lp2TVL.baseTVL).to.eq(isCall ? 0 : amountToTransfer);
          expect(totalTVL.underlyingTVL).to.eq(isCall ? amount : 0);
          expect(totalTVL.baseTVL).to.eq(isCall ? 0 : amount);
        });

        it('should not change user TVL if option long token is transferred', async () => {
          const amountNb = isCall ? 10 : 100000;
          const amount = parseOption(amountNb.toString(), isCall);
          await p.depositLiquidity(lp1, amount, isCall);

          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

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
              p.getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
            );
          const tokenIds = getOptionTokenIds(maturity, strike64x64, isCall);

          await pool
            .connect(buyer)
            .safeTransferFrom(
              buyer.address,
              lp2.address,
              tokenIds.long,
              purchaseAmount.div(2),
              '0x',
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

        it('should transfer user TVL if option short token is transferred', async () => {
          const amountNb = isCall ? 10 : 100000;
          const amount = parseOption(amountNb.toString(), isCall);
          await p.depositLiquidity(lp1, amount, isCall);

          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

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
              p.getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
            );
          const tokenIds = getOptionTokenIds(maturity, strike64x64, isCall);

          await pool
            .connect(lp1)
            .safeTransferFrom(
              lp1.address,
              lp2.address,
              tokenIds.short,
              purchaseAmount.div(4),
              '0x',
            );

          const user1TVL = await p.pool.getUserTVL(lp1.address);
          const user2TVL = await p.pool.getUserTVL(lp2.address);
          const totalTVL = await p.pool.getTotalTVL();
          const baseCost = fixedToNumber(quote.baseCost64x64);

          expect(formatOptionToNb(user1TVL.underlyingTVL, isCall)).to.almost(
            isCall ? 9 + baseCost : 0,
          );
          expect(formatOptionToNb(user1TVL.baseTVL, isCall)).to.almost(
            isCall ? 0 : amountNb + baseCost - p.getStrike(isCall, spotPrice),
          );
          expect(formatOptionToNb(user2TVL.underlyingTVL, isCall)).to.almost(
            isCall ? 1 : 0,
          );
          expect(formatOptionToNb(user2TVL.baseTVL, isCall)).to.almost(
            isCall ? 0 : p.getStrike(isCall, spotPrice),
          );
          expect(formatOptionToNb(totalTVL.underlyingTVL, isCall)).to.almost(
            isCall ? amountNb + baseCost : 0,
          );
          expect(formatOptionToNb(totalTVL.baseTVL, isCall)).to.almost(
            isCall ? 0 : amountNb + baseCost,
          );
        });

        it('should decrease user TVL if buyer exercise option with profit', async () => {
          const amountNb = isCall ? 10 : 100000;
          const amount = parseOption(amountNb.toString(), isCall);
          const strike = getStrike(isCall);
          await p.depositLiquidity(lp1, amount, isCall);

          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

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
              p.getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
            );

          const price = isCall ? strike * 1.4 : strike * 0.7;
          await p.setUnderlyingPrice(parseUnits(price.toString(), 8));
          const tokenIds = getOptionTokenIds(maturity, strike64x64, isCall);

          await pool
            .connect(buyer)
            .exerciseFrom(buyer.address, tokenIds.long, parseUnderlying('1'));

          const exerciseValue = getExerciseValue(price, strike, 1, isCall);

          const userTVL = await p.pool.getUserTVL(lp1.address);
          const totalTVL = await p.pool.getTotalTVL();
          const baseCost = fixedToNumber(quote.baseCost64x64);
          const feeCost =
            (isCall ? 1 - exerciseValue : strike - exerciseValue) * FEE;

          expect(formatOptionToNb(userTVL.underlyingTVL, isCall)).to.almost(
            isCall ? amountNb + baseCost - exerciseValue - feeCost : 0,
          );
          expect(formatOptionToNb(userTVL.baseTVL, isCall)).to.almost(
            isCall ? 0 : amountNb + baseCost - exerciseValue - feeCost,
          );
          expect(formatOptionToNb(totalTVL.underlyingTVL, isCall)).to.almost(
            isCall ? amountNb + baseCost - exerciseValue - feeCost : 0,
          );
          expect(formatOptionToNb(totalTVL.baseTVL, isCall)).to.almost(
            isCall ? 0 : amountNb + baseCost - exerciseValue - feeCost,
          );
        });

        it('should decrease user TVL when free liquidity is moved as reserved liquidity', async () => {
          const amountNb = isCall ? 10 : 100000;
          const amount = parseOption(amountNb.toString(), isCall);
          await p.depositLiquidity(lp1, amount, isCall);
          await p.depositLiquidity(lp2, amount, isCall);

          const { timestamp } = await ethers.provider.getBlock('latest');

          await p.pool
            .connect(lp1)
            .setDivestmentTimestamp(timestamp + 25 * 3600, isCall);
          await increaseTimestamp(26 * 3600);

          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

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
              p.getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
            );

          const lp1TVL = await p.pool.getUserTVL(lp1.address);
          const lp2TVL = await p.pool.getUserTVL(lp2.address);
          const totalTVL = await p.pool.getTotalTVL();
          const baseCost = fixedToNumber(quote.baseCost64x64);

          expect(
            await p.pool.balanceOf(lp1.address, p.getFreeLiqTokenId(isCall)),
          ).to.eq(0);
          expect(
            await p.pool.balanceOf(
              lp1.address,
              p.getReservedLiqTokenId(isCall),
            ),
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
        });
      });
    }
  });
});
