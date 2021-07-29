import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  IPool,
  PoolMock,
  PoolMock__factory,
  PremiaFeeDiscount,
  PremiaFeeDiscount__factory,
  Proxy__factory,
} from '../../typechain';

import { describeBehaviorOfPool } from './Pool.behavior';
import chai, { expect } from 'chai';
import { increaseTimestamp, resetHardhat, setTimestamp } from '../utils/evm';
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
import {
  bnToNumber,
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
  TokenType,
} from '../utils/math';
import chaiAlmost from 'chai-almost';
import { BigNumber } from 'ethers';
import { ZERO_ADDRESS } from '../utils/constants';
import { describeBehaviorOfProxy } from '@solidstate/spec';

chai.use(chaiAlmost(0.02));

const oneMonth = 30 * 24 * 3600;

describe('PoolProxy', function () {
  let owner: SignerWithAddress;
  let lp1: SignerWithAddress;
  let lp2: SignerWithAddress;
  let buyer: SignerWithAddress;
  let thirdParty: SignerWithAddress;
  let feeReceiver: SignerWithAddress;

  let xPremia: ERC20Mock;
  let premiaFeeDiscount: PremiaFeeDiscount;

  let pool: IPool;
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

  beforeEach(async function () {
    await resetHardhat();
    [owner, lp1, lp2, buyer, thirdParty, feeReceiver] =
      await ethers.getSigners();

    //

    const erc20Factory = new ERC20Mock__factory(owner);

    premia = await erc20Factory.deploy('PREMIA', 18);
    xPremia = await erc20Factory.deploy('xPREMIA', 18);
    premiaFeeDiscount = await new PremiaFeeDiscount__factory(owner).deploy(
      xPremia.address,
    );

    await premiaFeeDiscount.setStakeLevels([
      { amount: parseEther('5000'), discount: 2500 }, // -25%
      { amount: parseEther('50000'), discount: 5000 }, // -50%
      { amount: parseEther('250000'), discount: 7500 }, // -75%
      { amount: parseEther('500000'), discount: 9500 }, // -95%
    ]);

    await premiaFeeDiscount.setStakePeriod(oneMonth, 10000);
    await premiaFeeDiscount.setStakePeriod(3 * oneMonth, 12500);
    await premiaFeeDiscount.setStakePeriod(6 * oneMonth, 15000);
    await premiaFeeDiscount.setStakePeriod(12 * oneMonth, 20000);

    p = await PoolUtil.deploy(
      owner,
      premia.address,
      spotPrice,
      feeReceiver.address,
      premiaFeeDiscount.address,
    );

    pool = p.pool;
    poolMock = PoolMock__factory.connect(p.pool.address, owner);
    poolWeth = p.poolWeth;
  });

  describeBehaviorOfProxy({
    deploy: async () => Proxy__factory.connect(p.pool.address, owner),
    implementationFunction: 'getPoolSettings()',
    implementationFunctionArgs: [],
  });

  describeBehaviorOfPool(
    {
      deploy: async () => pool,
      mintERC1155: undefined as any,
      burnERC1155: undefined as any,
    },
    ['::ERC1155Enumerable', '#transfer', '#transferFrom'],
  );

  describe('liquidity queue', () => {
    it('should add/remove from queue properly', async () => {
      let queue: number[] = [];

      const formatAddress = (value: number) => {
        return hexZeroPad(hexlify(value), 20);
      };
      const removeAddress = async (value: number) => {
        await poolMock.removeUnderwriter(formatAddress(value), true);
        queue = queue.filter((el) => el !== value);
        expect(await poolMock.getUnderwriter()).to.eq(
          formatAddress(queue.length ? queue[0] : 0),
        );
      };
      const addAddress = async (value: number) => {
        await poolMock.addUnderwriter(formatAddress(value), true);

        if (!queue.includes(value)) {
          queue.push(value);
        }

        expect(await poolMock.getUnderwriter()).to.eq(formatAddress(queue[0]));
      };

      let i = 1;
      while (i <= 9) {
        await addAddress(i);
        i++;
      }

      await removeAddress(3);
      await removeAddress(5);
      await addAddress(3);
      await addAddress(3);
      await addAddress(3);
      await removeAddress(1);
      await removeAddress(6);
      await removeAddress(6);
      await removeAddress(9);
      await addAddress(3);
      await addAddress(3);
      await addAddress(9);
      await addAddress(5);
      await addAddress(queue[0]);
      await addAddress(queue[0]);
      await addAddress(queue[queue.length - 1]);
      await addAddress(queue[queue.length - 1]);
      await removeAddress(queue[queue.length - 1]);
      await removeAddress(queue[queue.length - 1]);

      while (queue.length) {
        await removeAddress(queue[0]);
      }

      expect(await poolMock.getUnderwriter()).to.eq(ZERO_ADDRESS);
    });
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
            .setDivestmentTimestamp(timestamp + 25 * 3600);
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

  describe('#getPriceUpdateAfter', () => {
    const ONE_HOUR = 3600;
    const SEQUENCE_LENGTH = ONE_HOUR * 256;

    const BASE_TIMESTAMP = 1750 * SEQUENCE_LENGTH;

    // first timestamp of sequence
    const SEQUENCE_START = BASE_TIMESTAMP;
    const SEQUENCE_MID = BASE_TIMESTAMP + ONE_HOUR * 128;
    // first timestamp of last bucket of sequence
    const SEQUENCE_END = BASE_TIMESTAMP + ONE_HOUR * 256;

    const PRICE = 1234;

    const setPriceUpdate = async (timestamp: number, price: number) => {
      await poolMock.setPriceUpdate(timestamp, fixedFromFloat(price));
    };

    const getPriceAfter = async (timestamp: number) => {
      return fixedToNumber(await poolMock.getPriceUpdateAfter(timestamp));
    };

    it('returns price update stored at beginning of sequence', async () => {
      const timestamp = SEQUENCE_START;

      await setPriceUpdate(timestamp, PRICE);

      // check timestamp in future bucket

      expect(await getPriceAfter(timestamp + ONE_HOUR)).not.to.eq(PRICE);

      // check timestamps in same bucket

      expect(await getPriceAfter(timestamp)).to.eq(PRICE);
      expect(await getPriceAfter(timestamp + ONE_HOUR - 1)).to.eq(PRICE);

      // check timestamps in previous bucket

      expect(await getPriceAfter(timestamp - 1)).to.eq(PRICE);
      expect(await getPriceAfter(timestamp - ONE_HOUR)).to.eq(PRICE);

      // check timestamps earlier in same sequence

      expect(await getPriceAfter(timestamp - SEQUENCE_LENGTH / 4)).to.eq(PRICE);
      expect(await getPriceAfter(SEQUENCE_START)).to.eq(PRICE);

      // check timestamps in previous sequence

      expect(await getPriceAfter(SEQUENCE_START - SEQUENCE_LENGTH)).to.eq(
        PRICE,
      );
      expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_LENGTH)).to.eq(PRICE);
      expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_LENGTH)).to.eq(PRICE);

      // check timestamps in very old sequence

      expect(await getPriceAfter(SEQUENCE_START - SEQUENCE_LENGTH * 3)).to.eq(
        PRICE,
      );
      expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_LENGTH * 3)).to.eq(
        PRICE,
      );
      expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_LENGTH * 3)).to.eq(
        PRICE,
      );
    });

    it('returns price update stored mid sequence', async () => {
      const timestamp = SEQUENCE_MID;

      await setPriceUpdate(timestamp, PRICE);

      // check timestamp in future bucket

      expect(await getPriceAfter(timestamp + ONE_HOUR)).not.to.eq(PRICE);

      // check timestamps in same bucket

      expect(await getPriceAfter(timestamp)).to.eq(PRICE);
      expect(await getPriceAfter(timestamp + ONE_HOUR - 1)).to.eq(PRICE);

      // check timestamps in previous bucket

      expect(await getPriceAfter(timestamp - 1)).to.eq(PRICE);
      expect(await getPriceAfter(timestamp - ONE_HOUR)).to.eq(PRICE);

      // check timestamps earlier in same sequence

      expect(await getPriceAfter(timestamp - SEQUENCE_LENGTH / 4)).to.eq(PRICE);
      expect(await getPriceAfter(SEQUENCE_START)).to.eq(PRICE);

      // check timestamps in previous sequence

      expect(await getPriceAfter(SEQUENCE_START - SEQUENCE_LENGTH)).to.eq(
        PRICE,
      );
      expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_LENGTH)).to.eq(PRICE);
      expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_LENGTH)).to.eq(PRICE);

      // check timestamps in very old sequence

      expect(await getPriceAfter(SEQUENCE_START - SEQUENCE_LENGTH * 3)).to.eq(
        PRICE,
      );
      expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_LENGTH * 3)).to.eq(
        PRICE,
      );
      expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_LENGTH * 3)).to.eq(
        PRICE,
      );
    });

    it('returns price update stored at end of sequence', async () => {
      const timestamp = SEQUENCE_END;

      await setPriceUpdate(timestamp, PRICE);

      // check timestamp in future bucket

      expect(await getPriceAfter(timestamp + ONE_HOUR)).not.to.eq(PRICE);

      // check timestamps in same bucket

      expect(await getPriceAfter(timestamp)).to.eq(PRICE);
      expect(await getPriceAfter(timestamp + ONE_HOUR - 1)).to.eq(PRICE);

      // check timestamps in previous bucket

      expect(await getPriceAfter(timestamp - 1)).to.eq(PRICE);
      expect(await getPriceAfter(timestamp - ONE_HOUR)).to.eq(PRICE);

      // check timestamps earlier in same sequence

      expect(await getPriceAfter(timestamp - SEQUENCE_LENGTH / 4)).to.eq(PRICE);
      expect(await getPriceAfter(SEQUENCE_START)).to.eq(PRICE);

      // check timestamps in previous sequence

      expect(await getPriceAfter(SEQUENCE_START - SEQUENCE_LENGTH)).to.eq(
        PRICE,
      );
      expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_LENGTH)).to.eq(PRICE);
      expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_LENGTH)).to.eq(PRICE);

      // check timestamps in very old sequence

      expect(await getPriceAfter(SEQUENCE_START - SEQUENCE_LENGTH * 3)).to.eq(
        PRICE,
      );
      expect(await getPriceAfter(SEQUENCE_MID - SEQUENCE_LENGTH * 3)).to.eq(
        PRICE,
      );
      expect(await getPriceAfter(SEQUENCE_END - SEQUENCE_LENGTH * 3)).to.eq(
        PRICE,
      );
    });

    it('should return the first price update available', async () => {
      let { timestamp } = await ethers.provider.getBlock('latest');
      timestamp = (Math.floor(timestamp / 3600 / 256) - 1) * 3600 * 256;

      let bucket = Math.floor(timestamp / 3600);

      let offset = bucket & 255;
      expect(offset).to.eq(0);

      await setPriceUpdate(timestamp - ONE_HOUR * 10, 1);
      await setPriceUpdate(timestamp - ONE_HOUR * 2, 5);

      await setPriceUpdate(timestamp, 10);

      await setPriceUpdate(timestamp + ONE_HOUR * 50, 20);
      await setPriceUpdate(timestamp + ONE_HOUR * 255, 30);

      expect(await getPriceAfter(timestamp - ONE_HOUR * 20)).to.eq(1);
      expect(await getPriceAfter(timestamp - ONE_HOUR * 5)).to.eq(5);
      expect(await getPriceAfter(timestamp - ONE_HOUR)).to.eq(10);
      expect(await getPriceAfter(timestamp)).to.eq(10);
      expect(await getPriceAfter(timestamp + ONE_HOUR)).to.eq(20);
      expect(await getPriceAfter(timestamp + ONE_HOUR * 50)).to.eq(20);
      expect(await getPriceAfter(timestamp + ONE_HOUR * 51)).to.eq(30);
    });
  });

  describe('#getUnderlying', function () {
    it('returns underlying address', async () => {
      expect((await pool.getPoolSettings()).underlying).to.eq(
        p.underlying.address,
      );
    });
  });

  describe('#getBase', function () {
    it('returns base address', async () => {
      expect((await pool.getPoolSettings()).base).to.eq(p.base.address);
    });
  });

  describe('#quote', function () {
    it('should revert if no liquidity', async () => {
      const maturity = await p.getMaturity(17);
      const strike64x64 = fixedFromFloat(spotPrice * 1.25);

      await expect(
        pool.quote(
          ZERO_ADDRESS,
          maturity,
          strike64x64,
          parseUnderlying('1'),
          true,
        ),
      ).to.be.revertedWith('no liq');
    });

    describe('call', () => {
      it('should return price for given call option parameters', async () => {
        await p.depositLiquidity(owner, parseUnderlying('10'), true);

        const strike64x64 = fixedFromFloat(2500);
        let { timestamp } = await ethers.provider.getBlock('latest');

        const q = await pool.quote(
          ZERO_ADDRESS,
          timestamp + 10 * 24 * 3600,
          strike64x64,
          parseUnderlying('1'),
          true,
        );

        expect(fixedToNumber(q.baseCost64x64) * spotPrice).to.almost(117.49);
        expect(fixedToNumber(q.feeCost64x64)).to.almost.eq(
          fixedToNumber(q.baseCost64x64) * 0.01,
        );
        expect(fixedToNumber(q.cLevel64x64)).to.almost(3.64);
        expect(
          (fixedToNumber(q.baseCost64x64) * spotPrice) /
            fixedToNumber(q.cLevel64x64) /
            fixedToNumber(q.slippageCoefficient64x64),
        ).to.almost(30.65);
      });

      it('should return intrinsic value + 5% if option is priced with instant profit', async () => {
        const isCall = true;

        await p.depositLiquidity(
          owner,
          parseOption(isCall ? '100' : '100000', isCall),
          isCall,
        );
        await poolMock.setCLevel(isCall, fixedFromFloat('0.1'));

        const maturity = await p.getMaturity(10);
        const strike64x64 = fixedFromFloat(getStrike(!isCall));
        const purchaseAmountNb = 10;
        const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

        const quote = await pool.callStatic.quote(
          buyer.address,
          maturity,
          strike64x64,
          purchaseAmount,
          isCall,
        );

        const spot64x64 = fixedFromFloat(spotPrice);

        expect(strike64x64).to.be.lt(spot64x64);

        const intrinsicValue64x64 = spot64x64
          .sub(strike64x64)
          .mul(BigNumber.from(purchaseAmountNb))
          .div(BigNumber.from(spotPrice));

        expect(quote.baseCost64x64).to.equal(
          intrinsicValue64x64
            .mul(BigNumber.from('105'))
            .div(BigNumber.from('100')),
        );
      });
    });

    describe('put', () => {
      it('should return price for given put option parameters', async () => {
        await p.depositLiquidity(owner, parseBase('10000'), false);

        const strike64x64 = fixedFromFloat(1750);
        let { timestamp } = await ethers.provider.getBlock('latest');

        const q = await pool.quote(
          ZERO_ADDRESS,
          timestamp + 10 * 24 * 3600,
          strike64x64,
          parseUnderlying('1'),
          false,
        );

        expect(fixedToNumber(q.baseCost64x64)).to.almost(189.59);
        expect(fixedToNumber(q.feeCost64x64)).to.almost.eq(
          fixedToNumber(q.baseCost64x64) * 0.01,
        );
        expect(fixedToNumber(q.cLevel64x64)).to.almost(3.29);
        expect(
          fixedToNumber(q.baseCost64x64) /
            fixedToNumber(q.cLevel64x64) /
            fixedToNumber(q.slippageCoefficient64x64),
        ).to.almost(57.48);
      });

      it('should return intrinsic value + 5% if option is priced with instant profit', async () => {
        const isCall = false;

        await p.depositLiquidity(
          owner,
          parseOption(isCall ? '100' : '100000', isCall),
          isCall,
        );
        await poolMock.setCLevel(isCall, fixedFromFloat('0.1'));

        const maturity = await p.getMaturity(10);
        const strike64x64 = fixedFromFloat(getStrike(!isCall));
        const purchaseAmountNb = 10;
        const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

        const quote = await pool.callStatic.quote(
          buyer.address,
          maturity,
          strike64x64,
          purchaseAmount,
          isCall,
        );

        const spot64x64 = fixedFromFloat(spotPrice);

        expect(strike64x64).to.be.gt(spot64x64);

        const intrinsicValue64x64 = strike64x64
          .sub(spot64x64)
          .mul(BigNumber.from(purchaseAmountNb));

        // rounding error caused by ABDKMath64x64 operations
        expect(quote.baseCost64x64).to.be.closeTo(
          intrinsicValue64x64
            .mul(BigNumber.from('105'))
            .div(BigNumber.from('100')),
          1000,
        );
      });
    });
  });

  describe('#setDivestmentTimestamp', () => {
    it('todo');

    describe('reverts if', () => {
      it('timestamp is less than one day in future', async () => {
        let { timestamp } = await ethers.provider.getBlock('latest');

        await ethers.provider.send('evm_setNextBlockTimestamp', [++timestamp]);

        await expect(
          pool.setDivestmentTimestamp(timestamp + 86400 - 1),
        ).to.be.revertedWith('liq lock 1d');

        await ethers.provider.send('evm_setNextBlockTimestamp', [++timestamp]);

        await expect(pool.setDivestmentTimestamp(timestamp + 86400)).not.to.be
          .reverted;
      });
    });
  });

  describe('#deposit', function () {
    describe('call', () => {
      it('should grant sender share tokens with ERC20 deposit', async () => {
        await p.underlying.mint(owner.address, 100);
        await p.underlying.approve(pool.address, ethers.constants.MaxUint256);
        await expect(() => pool.deposit('100', true)).to.changeTokenBalance(
          p.underlying,
          owner,
          -100,
        );
        expect(
          await pool.balanceOf(owner.address, underlyingFreeLiqToken),
        ).to.eq(100);
      });

      it('should grant sender share tokens with WETH deposit', async () => {
        // Use WETH tokens
        await p.weth.deposit({ value: 100 });
        await p.weth.approve(poolWeth.address, ethers.constants.MaxUint256);
        await expect(() => poolWeth.deposit('50', true)).to.changeTokenBalance(
          p.weth,
          owner,
          -50,
        );

        // Use ETH
        await expect(() =>
          poolWeth.deposit('200', true, { value: 200 }),
        ).to.changeEtherBalance(owner, -200);

        // Use both ETH and WETH tokens
        await expect(() =>
          poolWeth.deposit('100', true, { value: 50 }),
        ).to.changeEtherBalance(owner, -50);

        expect(await p.weth.balanceOf(owner.address)).to.eq(0);
        expect(
          await poolWeth.balanceOf(owner.address, underlyingFreeLiqToken),
        ).to.eq(350);
      });

      it('should revert if user send ETH with a token deposit', async () => {
        await p.underlying.mint(owner.address, 100);
        await p.underlying.approve(pool.address, ethers.constants.MaxUint256);
        await expect(
          pool.deposit('100', true, { value: 1 }),
        ).to.be.revertedWith('not WETH deposit');
      });

      it('should revert if user send too much ETH with a WETH deposit', async () => {
        await expect(
          poolWeth.deposit('200', true, { value: 201 }),
        ).to.be.revertedWith('too much ETH sent');
      });
    });

    describe('put', () => {
      it('should grant sender share tokens with ERC20 deposit', async () => {
        await p.base.mint(owner.address, 100);
        await p.base.approve(pool.address, ethers.constants.MaxUint256);
        await expect(() => pool.deposit('100', false)).to.changeTokenBalance(
          p.base,
          owner,
          -100,
        );
        expect(await pool.balanceOf(owner.address, baseFreeLiqToken)).to.eq(
          100,
        );
      });
    });
  });

  describe('#withdraw', function () {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should fail withdrawing if < 1 day after deposit', async () => {
          await p.depositLiquidity(owner, 100, isCall);

          await expect(pool.withdraw('100', isCall)).to.be.revertedWith(
            'liq lock 1d',
          );

          await increaseTimestamp(23 * 3600);
          await expect(pool.withdraw('100', isCall)).to.be.revertedWith(
            'liq lock 1d',
          );
        });

        it('should return underlying tokens withdrawn by sender', async () => {
          await p.depositLiquidity(owner, 100, isCall);
          expect(await p.getToken(isCall).balanceOf(owner.address)).to.eq(0);

          await increaseTimestamp(24 * 3600 + 60);
          await pool.withdraw('100', isCall);
          expect(await p.getToken(isCall).balanceOf(owner.address)).to.eq(100);
          expect(
            await pool.balanceOf(owner.address, p.getFreeLiqTokenId(isCall)),
          ).to.eq(0);
        });

        it('should successfully withdraw reserved liquidity', async () => {
          // ToDo
          expect(false);
        });
      });
    }
  });

  describe('#purchase', function () {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should revert if contract size is less than minimum', async () => {
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await expect(
            pool
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('0.001'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('too small');
        });

        it('should revert if using a maturity less than 1 day in the future', async () => {
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = (await p.getMaturity(1)).sub(ethers.constants.One);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            pool
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('exp < 1 day');
        });

        it('should revert if using a maturity more than 28 days in the future', async () => {
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = await p.getMaturity(30);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            pool
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('exp > 28 days');
        });

        it('should revert if using a maturity not corresponding to end of UTC day', async () => {
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = (await p.getMaturity(10)).add(3600);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            pool
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('exp not end UTC day');
        });

        it('should revert if using a strike > 1.5x spot', async () => {
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(spotPrice * 2.01);

          await expect(
            pool
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('strike > 1.5x spot');
        });

        it('should revert if using a strike < 0.75x spot', async () => {
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(spotPrice * 0.49);

          await expect(
            pool
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('strike < 0.75x spot');
        });

        it('should revert if cost is above max cost', async () => {
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await p
            .getToken(isCall)
            .mint(buyer.address, parseOption('100', isCall));
          await p
            .getToken(isCall)
            .connect(buyer)
            .approve(pool.address, ethers.constants.MaxUint256);

          await expect(
            pool
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('0.01', isCall),
              ),
          ).to.be.revertedWith('excess slip');
        });

        it('should successfully purchase an option', async () => {
          await p.depositLiquidity(
            lp1,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );

          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          const purchaseAmountNb = 10;
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

          const newBalance = await p.getToken(isCall).balanceOf(buyer.address);

          expect(bnToNumber(newBalance, getTokenDecimals(isCall))).to.almost(
            bnToNumber(mintAmount, getTokenDecimals(isCall)) -
              fixedToNumber(quote.baseCost64x64) -
              fixedToNumber(quote.feeCost64x64),
          );

          const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

          if (isCall) {
            expect(
              bnToNumber(
                await pool.balanceOf(lp1.address, p.getFreeLiqTokenId(isCall)),
                DECIMALS_UNDERLYING,
              ),
            ).to.almost(
              100 - purchaseAmountNb + fixedToNumber(quote.baseCost64x64),
            );
          } else {
            expect(
              bnToNumber(
                await pool.balanceOf(lp1.address, p.getFreeLiqTokenId(isCall)),
                DECIMALS_BASE,
              ),
            ).to.almost(
              100000 -
                purchaseAmountNb * getStrike(isCall) +
                fixedToNumber(quote.baseCost64x64),
            );
          }

          expect(
            bnToNumber(
              await pool.balanceOf(
                feeReceiver.address,
                p.getReservedLiqTokenId(isCall),
              ),
            ),
          ).to.almost(fixedToNumber(quote.feeCost64x64));

          expect(await pool.balanceOf(lp1.address, tokenId.long)).to.eq(0);
          expect(await pool.balanceOf(lp1.address, tokenId.short)).to.eq(
            purchaseAmount,
          );

          expect(await pool.balanceOf(buyer.address, tokenId.long)).to.eq(
            purchaseAmount,
          );
          expect(await pool.balanceOf(buyer.address, tokenId.short)).to.eq(0);
        });

        it('should successfully purchase an option from multiple LP intervals', async () => {
          const signers = await ethers.getSigners();

          let amountInPool = BigNumber.from(0);
          let depositAmountNb = isCall ? 1 : 2000;
          let depositAmount = parseOption(depositAmountNb.toString(), isCall);
          for (const signer of signers) {
            if (signer.address == buyer.address) continue;

            await p.depositLiquidity(signer, depositAmount, isCall);
            amountInPool = amountInPool.add(depositAmount);
          }

          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          // 10 intervals used
          const purchaseAmountNb = 10;
          const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

          const quote = await pool.quote(
            buyer.address,
            maturity,
            strike64x64,
            purchaseAmount,
            isCall,
          );

          await p
            .getToken(isCall)
            .mint(buyer.address, parseOption('10000', isCall));
          await p
            .getToken(isCall)
            .connect(buyer)
            .approve(pool.address, ethers.constants.MaxUint256);

          const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

          const tx = await pool
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
              p.getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
            );

          expect(await pool.balanceOf(buyer.address, tokenId.long)).to.eq(
            purchaseAmount,
          );

          let amount = purchaseAmountNb;

          let i = 0;
          for (const s of signers) {
            if (s.address === buyer.address) continue;

            let expectedAmount = 0;

            const totalToPay = isCall
              ? purchaseAmountNb
              : purchaseAmountNb * getStrike(isCall);
            const intervalAmount =
              (depositAmountNb *
                (totalToPay + fixedToNumber(quote.baseCost64x64))) /
              totalToPay /
              (isCall ? 1 : getStrike(isCall));

            if (intervalAmount < amount) {
              expectedAmount = intervalAmount;
              amount -= intervalAmount;
            } else {
              expectedAmount = amount;
              amount = 0;
            }

            expect(
              bnToNumber(
                await pool.balanceOf(s.address, tokenId.short),
                DECIMALS_UNDERLYING,
              ),
            ).to.almost(expectedAmount);

            i++;
          }

          const r = await tx.wait(1);
        });
      });
    }
  });

  describe('#exerciseFrom', function () {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should revert if token is a SHORT token', async () => {
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await p.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            strike64x64,
            isCall,
          );

          const shortTokenId = formatTokenId({
            tokenType: p.getShort(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            pool
              .connect(buyer)
              .exerciseFrom(buyer.address, shortTokenId, parseUnderlying('1')),
          ).to.be.revertedWith('invalid type');
        });

        it('should revert if option is not ITM', async () => {
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await p.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: p.getLong(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            pool
              .connect(buyer)
              .exerciseFrom(buyer.address, longTokenId, parseUnderlying('1')),
          ).to.be.revertedWith('not ITM');
        });

        it('should successfully apply staking fee discount on exercise', async () => {
          const maturity = await p.getMaturity(10);
          const strike = getStrike(isCall);
          const strike64x64 = fixedFromFloat(strike);
          const amountNb = 10;
          const amount = parseUnderlying(amountNb.toString());
          const initialFreeLiqAmount = isCall
            ? amount
            : parseBase(formatUnderlying(amount)).mul(
                fixedToNumber(strike64x64),
              );

          const quote = await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          // Stake xPremia for fee discount
          await xPremia.mint(buyer.address, parseEther('5000'));
          await xPremia.mint(lp1.address, parseEther('50000'));
          await xPremia
            .connect(buyer)
            .approve(premiaFeeDiscount.address, ethers.constants.MaxUint256);
          await xPremia
            .connect(lp1)
            .approve(premiaFeeDiscount.address, ethers.constants.MaxUint256);
          await premiaFeeDiscount
            .connect(buyer)
            .stake(parseEther('5000'), oneMonth);
          await premiaFeeDiscount
            .connect(lp1)
            .stake(parseEther('50000'), oneMonth);

          //

          expect(await premiaFeeDiscount.getDiscount(buyer.address)).to.eq(
            2500,
          );
          expect(await premiaFeeDiscount.getDiscount(lp1.address)).to.eq(5000);

          const longTokenId = formatTokenId({
            tokenType: p.getLong(isCall),
            maturity,
            strike64x64,
          });

          const price = isCall ? strike * 1.4 : strike * 0.7;
          await p.setUnderlyingPrice(parseUnits(price.toString(), 8));

          const curBalance = await p.getToken(isCall).balanceOf(buyer.address);

          await pool
            .connect(buyer)
            .exerciseFrom(buyer.address, longTokenId, amount);

          const exerciseValue = getExerciseValue(
            price,
            strike,
            amountNb,
            isCall,
          );
          const premium = (
            await p.getToken(isCall).balanceOf(buyer.address)
          ).sub(curBalance);

          expect(Number(formatOption(premium, isCall))).to.almost(
            exerciseValue * (1 - FEE * 0.75),
          );
          expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(0);

          const freeLiqAfter = await pool.balanceOf(
            lp1.address,
            p.getFreeLiqTokenId(isCall),
          );

          // Free liq = initial amount + premia paid
          expect(
            (Number(formatOption(initialFreeLiqAmount, isCall)) -
              exerciseValue) *
              (1 - FEE * 0.5) +
              fixedToNumber(quote.baseCost64x64),
          ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
        });

        it('should successfully exercise', async () => {
          const maturity = await p.getMaturity(10);
          const strike = getStrike(isCall);
          const strike64x64 = fixedFromFloat(strike);
          const amountNb = 10;
          const amount = parseUnderlying(amountNb.toString());
          const initialFreeLiqAmount = isCall
            ? amount
            : parseBase(formatUnderlying(amount)).mul(
                fixedToNumber(strike64x64),
              );

          const quote = await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: p.getLong(isCall),
            maturity,
            strike64x64,
          });

          const price = isCall ? strike * 1.4 : strike * 0.7;
          await p.setUnderlyingPrice(parseUnits(price.toString(), 8));

          const curBalance = await p.getToken(isCall).balanceOf(buyer.address);

          await pool
            .connect(buyer)
            .exerciseFrom(buyer.address, longTokenId, amount);

          const exerciseValue = getExerciseValue(
            price,
            strike,
            amountNb,
            isCall,
          );
          const premium = (
            await p.getToken(isCall).balanceOf(buyer.address)
          ).sub(curBalance);

          expect(Number(formatOption(premium, isCall))).to.almost(
            exerciseValue * (1 - FEE),
          );
          expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(0);

          const freeLiqAfter = await pool.balanceOf(
            lp1.address,
            p.getFreeLiqTokenId(isCall),
          );

          // Free liq = initial amount + premia paid
          expect(
            (Number(formatOption(initialFreeLiqAmount, isCall)) -
              exerciseValue) *
              (1 - FEE) +
              fixedToNumber(quote.baseCost64x64),
          ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
        });

        it('should revert when exercising on behalf of user not approved', async () => {
          const maturity = await p.getMaturity(10);
          const strike = getStrike(isCall);
          const strike64x64 = fixedFromFloat(strike);
          const amountNb = 10;
          const amount = parseUnderlying(amountNb.toString());

          await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: p.getLong(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            pool
              .connect(thirdParty)
              .exerciseFrom(buyer.address, longTokenId, amount),
          ).to.be.revertedWith('not approved');
        });

        it('should succeed when exercising on behalf of user approved', async () => {
          const maturity = await p.getMaturity(10);
          const strike = getStrike(isCall);
          const strike64x64 = fixedFromFloat(strike);
          const amountNb = 10;
          const amount = parseUnderlying(amountNb.toString());
          const initialFreeLiqAmount = isCall
            ? amount
            : parseBase(formatUnderlying(amount)).mul(
                fixedToNumber(strike64x64),
              );

          const quote = await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: p.getLong(isCall),
            maturity,
            strike64x64,
          });

          const price = isCall ? strike * 1.4 : strike * 0.7;
          await p.setUnderlyingPrice(parseUnits(price.toString(), 8));

          const curBalance = await p.getToken(isCall).balanceOf(buyer.address);

          await pool.connect(buyer).setApprovalForAll(thirdParty.address, true);

          await pool
            .connect(thirdParty)
            .exerciseFrom(buyer.address, longTokenId, amount);

          const exerciseValue = getExerciseValue(
            price,
            strike,
            amountNb,
            isCall,
          );
          const premium = (
            await p.getToken(isCall).balanceOf(buyer.address)
          ).sub(curBalance);
          expect(Number(formatOption(premium, isCall))).to.almost(
            exerciseValue * (1 - FEE),
          );

          expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(0);

          const freeLiqAfter = await pool.balanceOf(
            lp1.address,
            p.getFreeLiqTokenId(isCall),
          );

          // Free liq = initial amount + premia paid
          expect(
            (Number(formatOption(initialFreeLiqAmount, isCall)) -
              exerciseValue) *
              (1 - FEE) +
              fixedToNumber(quote.baseCost64x64),
          ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
        });
      });
    }
  });

  describe('#processExpired', function () {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should revert if option is not expired', async () => {
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await p.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: p.getLong(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            pool
              .connect(buyer)
              .processExpired(longTokenId, parseUnderlying('1')),
          ).to.be.revertedWith('not expired');
        });

        it('should successfully process expired option OTM', async () => {
          const maturity = await p.getMaturity(20);
          const strike = getStrike(isCall);
          const strike64x64 = fixedFromFloat(strike);

          const amount = parseUnderlying('1');
          const initialFreeLiqAmount = isCall
            ? amount
            : parseBase(formatUnderlying(amount)).mul(
                fixedToNumber(strike64x64),
              );
          const initialBuyerAmount = isCall
            ? parseUnderlying('100')
            : parseBase('10000');

          const quote = await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          await setTimestamp(maturity.add(100).toNumber());

          const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

          const price = isCall ? strike * 0.7 : strike * 1.4;
          await p.setUnderlyingPrice(parseUnits(price.toString(), 8));

          // Free liq = premia paid after purchase
          expect(
            Number(
              formatOption(
                await pool.balanceOf(lp1.address, p.getFreeLiqTokenId(isCall)),
                isCall,
              ),
            ),
          ).to.almost(fixedToNumber(quote.baseCost64x64));

          // Process expired
          await pool
            .connect(buyer)
            .processExpired(tokenId.long, parseUnderlying('1'));

          expect(await pool.balanceOf(buyer.address, tokenId.long)).to.eq(0);
          expect(await pool.balanceOf(lp1.address, tokenId.short)).to.eq(0);

          // Buyer balance = initial amount - premia paid
          expect(
            Number(
              formatOption(
                await p.getToken(isCall).balanceOf(buyer.address),
                isCall,
              ),
            ),
          ).to.almost(
            Number(formatOption(initialBuyerAmount, isCall)) -
              fixedToNumber(quote.baseCost64x64) -
              fixedToNumber(quote.feeCost64x64),
          );

          const freeLiqAfter = await pool.balanceOf(
            lp1.address,
            p.getFreeLiqTokenId(isCall),
          );

          // Free liq = initial amount + premia paid
          expect(
            Number(formatOption(initialFreeLiqAmount, isCall)) * (1 - FEE) +
              fixedToNumber(quote.baseCost64x64),
          ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
        });

        it('should successfully process expired option ITM', async () => {
          const maturity = await p.getMaturity(20);
          const strike = getStrike(isCall);
          const strike64x64 = fixedFromFloat(strike);

          const amount = parseUnderlying('1');
          const initialFreeLiqAmount = isCall
            ? amount
            : parseBase(formatUnderlying(amount)).mul(
                fixedToNumber(strike64x64),
              );
          const initialBuyerAmount = isCall
            ? parseUnderlying('100')
            : parseBase('10000');

          const quote = await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          await setTimestamp(maturity.add(100).toNumber());

          const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

          const price = isCall ? strike * 1.4 : strike * 0.7;
          await p.setUnderlyingPrice(parseUnits(price.toString(), 8));

          // Free liq = premia paid after purchase
          expect(
            Number(
              formatOption(
                await pool.balanceOf(lp1.address, p.getFreeLiqTokenId(isCall)),
                isCall,
              ),
            ),
          ).to.almost(fixedToNumber(quote.baseCost64x64));

          // Process expired
          await pool
            .connect(buyer)
            .processExpired(tokenId.long, parseUnderlying('1'));

          expect(await pool.balanceOf(buyer.address, tokenId.long)).to.eq(0);
          expect(await pool.balanceOf(lp1.address, tokenId.short)).to.eq(0);

          const exerciseValue = getExerciseValue(price, strike, 1, isCall);

          // Buyer balance = initial amount - premia paid + exercise value
          expect(
            Number(
              formatOption(
                await p.getToken(isCall).balanceOf(buyer.address),
                isCall,
              ),
            ),
          ).to.almost(
            Number(formatOption(initialBuyerAmount, isCall)) -
              fixedToNumber(quote.baseCost64x64) -
              fixedToNumber(quote.feeCost64x64) +
              exerciseValue * (1 - FEE),
          );

          const freeLiqAfter = await pool.balanceOf(
            lp1.address,
            p.getFreeLiqTokenId(isCall),
          );

          // Free liq = initial amount + premia paid - exerciseValue
          expect(
            (Number(formatOption(initialFreeLiqAmount, isCall)) -
              exerciseValue) *
              (1 - FEE) +
              fixedToNumber(quote.baseCost64x64),
          ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
        });
      });
    }
  });

  describe('#getTokenIds', function () {
    it('should correctly list existing tokenIds', async () => {
      const isCall = true;

      const maturity = await p.getMaturity(20);
      const strike = getStrike(isCall);
      const strike64x64 = fixedFromFloat(strike);
      const amount = parseUnderlying('1');

      await p.purchaseOption(lp1, buyer, amount, maturity, strike64x64, isCall);

      const optionId = getOptionTokenIds(maturity, strike64x64, isCall);

      let tokenIds = await pool.getTokenIds();
      expect(tokenIds.length).to.eq(4);
      expect(tokenIds[0]).to.eq(p.getFreeLiqTokenId(isCall));
      expect(tokenIds[1]).to.eq(optionId.long);
      expect(tokenIds[2]).to.eq(optionId.short);
      expect(tokenIds[3]).to.eq(p.getReservedLiqTokenId(isCall));

      await setTimestamp(maturity.add(100).toNumber());

      const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

      const price = isCall ? strike * 0.7 : strike * 1.4;
      await p.setUnderlyingPrice(parseUnits(price.toString(), 8));

      await pool
        .connect(buyer)
        .processExpired(tokenId.long, parseUnderlying('1'));

      tokenIds = await pool.getTokenIds();
      expect(tokenIds.length).to.eq(2);
      expect(tokenIds[0]).to.eq(p.getFreeLiqTokenId(isCall));
      expect(tokenIds[1]).to.eq(p.getReservedLiqTokenId(isCall));
    });
  });

  describe('#reassign', function () {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should revert if contract size is less than minimum', async () => {
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await p.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            strike64x64,
            isCall,
          );

          const shortTokenId = formatTokenId({
            tokenType: p.getShort(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            pool.connect(lp1).reassign(shortTokenId, '1'),
          ).to.be.revertedWith('too small');
        });

        it('should revert if option is expired', async () => {
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await p.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            strike64x64,
            isCall,
          );

          const shortTokenId = formatTokenId({
            tokenType: p.getShort(isCall),
            maturity,
            strike64x64,
          });

          const shortTokenBalance = await pool.balanceOf(
            lp1.address,
            shortTokenId,
          );

          await increaseTimestamp(11 * 24 * 3600);

          await expect(
            pool.connect(lp1).reassign(shortTokenId, shortTokenBalance),
          ).to.be.revertedWith('expired');
        });

        it('should successfully reassign option to another LP', async () => {
          const maturity = await p.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));
          const amount = parseUnderlying('1');

          await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          await p.depositLiquidity(
            lp2,
            isCall
              ? parseUnderlying('1').mul(2)
              : parseBase('1').mul(fixedToNumber(strike64x64)).mul(2),
            isCall,
          );

          await increaseTimestamp(25 * 3600);

          const shortTokenId = formatTokenId({
            tokenType: p.getShort(isCall),
            maturity,
            strike64x64,
          });

          const shortTokenBalance = await pool.balanceOf(
            lp1.address,
            shortTokenId,
          );

          await pool
            .connect(lp1)
            .withdrawAllAndReassignBatch(
              isCall,
              [shortTokenId],
              [shortTokenBalance],
            );

          expect(
            await pool.balanceOf(lp1.address, p.getFreeLiqTokenId(isCall)),
          ).to.eq(0);
          expect(await pool.balanceOf(lp1.address, shortTokenId)).to.eq(0);
          expect(await pool.balanceOf(lp2.address, shortTokenId)).to.eq(
            shortTokenBalance,
          );
        });
      });
    }
  });

  describe('#reassignBatch', function () {
    it('todo');

    it('should revert if contract size is less than minimum', async () => {
      const isCall = true;
      const maturity = await p.getMaturity(10);
      const strike64x64 = fixedFromFloat(getStrike(isCall));

      await p.purchaseOption(
        lp1,
        buyer,
        parseUnderlying('1'),
        maturity,
        strike64x64,
        isCall,
      );

      const shortTokenId = formatTokenId({
        tokenType: p.getShort(isCall),
        maturity,
        strike64x64,
      });

      await expect(
        pool.connect(lp1).reassignBatch([shortTokenId], ['1']),
      ).to.be.revertedWith('too small');
    });
  });

  describe('#withdrawAllAndReassignBatch', function () {
    it('todo');
  });

  describe('#write', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should revert if trying to manually underwrite an option from a non approved operator', async () => {
          const amount = parseUnderlying('1');
          await expect(
            p.writeOption(
              owner,
              lp1,
              lp2,
              await p.getMaturity(30),
              fixedFromFloat(2),
              amount,
              isCall,
            ),
          ).to.be.revertedWith('not approved');
        });

        it('should successfully manually underwrite an option without use of an external operator', async () => {
          const amount = parseUnderlying('1');
          await p.writeOption(
            lp1,
            lp1,
            lp2,
            await p.getMaturity(30),
            fixedFromFloat(2),
            amount,
            isCall,
          );

          const tokenIds = getOptionTokenIds(
            await p.getMaturity(30),
            fixedFromFloat(2),
            isCall,
          );

          expect(await p.getToken(isCall).balanceOf(lp1.address)).to.eq(0);
          expect(await pool.balanceOf(lp1.address, tokenIds.long)).to.eq(0);
          expect(await pool.balanceOf(lp2.address, tokenIds.long)).to.eq(
            amount,
          );
          expect(await pool.balanceOf(lp1.address, tokenIds.short)).to.eq(
            amount,
          );
          expect(await pool.balanceOf(lp2.address, tokenIds.short)).to.eq(0);
        });

        it('should successfully manually underwrite an option with use of an external operator', async () => {
          const amount = parseUnderlying('1');
          await pool.connect(lp1).setApprovalForAll(owner.address, true);
          await p.writeOption(
            owner,
            lp1,
            lp2,
            await p.getMaturity(30),
            fixedFromFloat(2),
            amount,
            isCall,
          );

          const tokenIds = getOptionTokenIds(
            await p.getMaturity(30),
            fixedFromFloat(2),
            isCall,
          );

          expect(await p.getToken(isCall).balanceOf(lp1.address)).to.eq(0);
          expect(await pool.balanceOf(lp1.address, tokenIds.long)).to.eq(0);
          expect(await pool.balanceOf(lp2.address, tokenIds.long)).to.eq(
            amount,
          );
          expect(await pool.balanceOf(lp1.address, tokenIds.short)).to.eq(
            amount,
          );
          expect(await pool.balanceOf(lp2.address, tokenIds.short)).to.eq(0);
        });
      });
    }
  });

  describe('#annihilate', () => {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should successfully burn long and short tokens + withdraw collateral', async () => {
          const amount = parseUnderlying('1');
          await p.writeOption(
            lp1,
            lp1,
            lp1,
            await p.getMaturity(30),
            fixedFromFloat(2),
            amount,
            isCall,
          );

          const tokenIds = getOptionTokenIds(
            await p.getMaturity(30),
            fixedFromFloat(2),
            isCall,
          );

          expect(await pool.balanceOf(lp1.address, tokenIds.long)).to.eq(
            amount,
          );
          expect(await pool.balanceOf(lp1.address, tokenIds.short)).to.eq(
            amount,
          );
          expect(await p.getToken(isCall).balanceOf(lp1.address)).to.eq(0);

          await pool.connect(lp1).annihilate(tokenIds.short, amount);

          expect(await pool.balanceOf(lp1.address, tokenIds.long)).to.eq(0);
          expect(await pool.balanceOf(lp1.address, tokenIds.short)).to.eq(0);
          expect(await p.getToken(isCall).balanceOf(lp1.address)).to.eq(
            isCall ? amount : parseBase('2'),
          );
        });
      });
    }
  });

  describe('#safeTransferFrom', () => {
    it('reverts if tokenId corresponds to locked free liquidity', async () => {
      await p.depositLiquidity(owner, parseOption('100', true), true);

      expect(
        pool
          .connect(owner)
          .safeTransferFrom(
            owner.address,
            owner.address,
            p.getFreeLiqTokenId(true),
            '1',
            ethers.utils.randomBytes(0),
          ),
      ).to.be.revertedWith('liq lock 1d');
    });

    it('reverts if tokenId corresponds to locked reserved liquidity', async () => {
      await p.depositLiquidity(owner, parseOption('100', true), true);

      expect(
        pool
          .connect(owner)
          .safeTransferFrom(
            owner.address,
            owner.address,
            p.getReservedLiqTokenId(true),
            '1',
            ethers.utils.randomBytes(0),
          ),
      ).to.be.revertedWith('liq lock 1d');
    });
  });
});
