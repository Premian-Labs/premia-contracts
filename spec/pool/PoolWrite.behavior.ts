import { ethers } from 'hardhat';
import { expect } from 'chai';
import { IPool, ERC20Mock } from '../../typechain';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
} from '@premia/utils';

import { bnToNumber } from '../../test/utils/math';

import {
  createUniswapPair,
  depositUniswapLiquidity,
  IUniswap,
} from '../../test/utils/uniswap';

import {
  DECIMALS_BASE,
  DECIMALS_UNDERLYING,
  FEE_APY,
  ONE_YEAR,
  formatOption,
  formatUnderlying,
  formatBase,
  getTokenDecimals,
  parseBase,
  parseOption,
  parseUnderlying,
  getFreeLiqTokenId,
  getReservedLiqTokenId,
  getShort,
  getLong,
  getStrike,
  getMaturity,
  getMinPrice,
  getMaxCost,
  PoolUtil,
} from '../../test/pool/PoolUtil';

interface PoolWriteBehaviorArgs {
  deploy: () => Promise<IPool>;
  getBase: () => Promise<ERC20Mock>;
  getUnderlying: () => Promise<ERC20Mock>;
  getPoolUtil: () => Promise<PoolUtil>;
  getUniswap: () => Promise<IUniswap>;
}

export function describeBehaviorOfPoolWrite({
  deploy,
  getBase,
  getUnderlying,
  getPoolUtil,
  getUniswap,
}: PoolWriteBehaviorArgs) {
  describe('::PoolWrite', () => {
    let owner: SignerWithAddress;
    let buyer: SignerWithAddress;
    let lp1: SignerWithAddress;
    let lp2: SignerWithAddress;
    // TODO: pass as arg
    let feeReceiver: SignerWithAddress;
    let instance: IPool;
    let base: ERC20Mock;
    let underlying: ERC20Mock;
    let p: PoolUtil;
    let uniswap: IUniswap;

    before(async () => {
      [owner, buyer, lp1, lp2] = await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
      // TODO: don't
      p = await getPoolUtil();
      uniswap = await getUniswap();
      feeReceiver = p.feeReceiver;
      base = await getBase();
      underlying = await getUnderlying();
    });

    describe('#quote', function () {
      it('should revert if no liquidity', async () => {
        const maturity = await getMaturity(17);
        const strike64x64 = fixedFromFloat(2000 * 1.25);

        await expect(
          instance.quote(
            ethers.constants.AddressZero,
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

          const q = await instance.quote(
            ethers.constants.AddressZero,
            timestamp + 10 * 24 * 3600,
            strike64x64,
            parseUnderlying('1'),
            true,
          );

          expect(fixedToNumber(q.baseCost64x64) * 2000).to.almost(24.62);
          expect(fixedToNumber(q.feeCost64x64)).to.almost.eq(
            fixedToNumber(q.baseCost64x64) * 0.01,
          );
          expect(fixedToNumber(q.cLevel64x64)).to.almost(1.82);
          expect(
            (fixedToNumber(q.baseCost64x64) * 2000) /
              fixedToNumber(q.cLevel64x64) /
              fixedToNumber(q.slippageCoefficient64x64),
          ).to.almost(12.85);
        });

        it('should return min price based on min apy, if option is priced under', async () => {
          await p.depositLiquidity(owner, parseUnderlying('10'), true);

          const strike = 3900;
          const strike64x64 = fixedFromFloat(strike);
          let { timestamp } = await ethers.provider.getBlock('latest');
          const maturity = timestamp + 24 * 3600;

          const q = await instance.quote(
            ethers.constants.AddressZero,
            maturity,
            strike64x64,
            parseUnderlying('1'),
            true,
          );

          expect(fixedToNumber(q.baseCost64x64)).to.almost(
            await getMinPrice(1, maturity),
          );
        });

        it('should return intrinsic value + min price if option is priced with instant profit', async () => {
          const isCall = true;

          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          await instance
            .connect(owner)
            .setCLevel64x64(fixedFromFloat('0.1'), isCall);

          const maturity = await getMaturity(5);
          const strike64x64 = fixedFromFloat(getStrike(!isCall, 2000));
          const purchaseAmountNb = 10;
          const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

          const quote = await instance.callStatic.quote(
            buyer.address,
            maturity,
            strike64x64,
            purchaseAmount,
            isCall,
          );

          const spot64x64 = fixedFromFloat(2000);

          expect(strike64x64).to.be.lt(spot64x64);

          const intrinsicValue64x64 = spot64x64
            .sub(strike64x64)
            .mul(BigNumber.from(purchaseAmountNb))
            .div(BigNumber.from(2000));

          expect(fixedToNumber(quote.baseCost64x64)).to.almost(
            fixedToNumber(intrinsicValue64x64) +
              (await getMinPrice(purchaseAmountNb, maturity.toNumber())),
          );
        });
      });

      describe('put', () => {
        it('should return price for given put option parameters', async () => {
          await p.depositLiquidity(owner, parseBase('10000'), false);

          const strike64x64 = fixedFromFloat(1750);
          let { timestamp } = await ethers.provider.getBlock('latest');

          const q = await instance.quote(
            ethers.constants.AddressZero,
            timestamp + 10 * 24 * 3600,
            strike64x64,
            parseUnderlying('1'),
            false,
          );

          expect(fixedToNumber(q.baseCost64x64)).to.almost(45.14);
          expect(fixedToNumber(q.feeCost64x64)).to.almost.eq(
            fixedToNumber(q.baseCost64x64) * 0.03,
          );
          expect(fixedToNumber(q.cLevel64x64)).to.almost(1.98);
          expect(
            fixedToNumber(q.baseCost64x64) /
              fixedToNumber(q.cLevel64x64) /
              fixedToNumber(q.slippageCoefficient64x64),
          ).to.almost(21.03);
        });

        it('should return min price based on min apy, if option is priced under', async () => {
          await p.depositLiquidity(owner, parseBase('100000'), false);

          const strike = 1500;
          const strike64x64 = fixedFromFloat(strike);
          let { timestamp } = await ethers.provider.getBlock('latest');
          const maturity = timestamp + 24 * 3600;

          const q = await instance.quote(
            ethers.constants.AddressZero,
            maturity,
            strike64x64,
            parseUnderlying('1'),
            false,
          );

          expect(fixedToNumber(q.baseCost64x64)).to.almost(
            await getMinPrice(strike, maturity),
          );
        });

        it('should return intrinsic value + min price if option is priced with instant profit', async () => {
          const isCall = false;

          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          await instance
            .connect(owner)
            .setCLevel64x64(fixedFromFloat('0.1'), isCall);

          const maturity = await getMaturity(5);
          const strike64x64 = fixedFromFloat(getStrike(!isCall, 2000));
          const purchaseAmountNb = 5;
          const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

          const quote = await instance.callStatic.quote(
            buyer.address,
            maturity,
            strike64x64,
            purchaseAmount,
            isCall,
          );

          const spot64x64 = fixedFromFloat(2000);

          expect(strike64x64).to.be.gt(spot64x64);

          const intrinsicValue64x64 = strike64x64
            .sub(spot64x64)
            .mul(BigNumber.from(purchaseAmountNb));

          expect(fixedToNumber(quote.baseCost64x64)).to.almost(
            fixedToNumber(intrinsicValue64x64) +
              (await getMinPrice(
                purchaseAmountNb * getStrike(!isCall, 2000),
                maturity.toNumber(),
              )),
            0.1,
          );
        });
      });
    });

    describe('#purchase', function () {
      describe('call option', () => {
        it('transfers cost to pool', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          await p.depositLiquidity(lp1, amount, isCall);

          await underlying.mint(buyer.address, parseUnderlying('100'));
          await underlying
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          const oldBuyerBalance = await underlying.callStatic.balanceOf(
            buyer.address,
          );
          const oldContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );

          const tx = await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const { events } = await tx.wait();
          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const newBuyerBalance = await underlying.callStatic.balanceOf(
            buyer.address,
          );
          const newContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );

          expect(newBuyerBalance).to.equal(
            oldBuyerBalance.sub(baseCost).sub(feeCost),
          );
          expect(newContractBalance).to.equal(
            oldContractBalance.add(baseCost).add(feeCost),
          );
        });

        it('mints long tokens for buyer and short tokens for underwriter', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = amount;

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await p.depositLiquidity(
            lp1,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

          await underlying.mint(buyer.address, parseUnderlying('100000'));
          await underlying
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          const oldBuyerLongTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            longTokenId,
          );
          const oldLPShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldLPFreeLiquidityBalance = await instance.callStatic.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );

          const tx = await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const { blockNumber, events } = await tx.wait();
          const { timestamp } = await ethers.provider.getBlock(blockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFee = maturity
            .sub(ethers.BigNumber.from(timestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newBuyerLongTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            longTokenId,
          );
          const newLPShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const newLPFreeLiquidityBalance = await instance.callStatic.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );

          expect(newBuyerLongTokenBalance).to.equal(
            oldBuyerLongTokenBalance.add(amount),
          );
          expect(newLPShortTokenBalance).to.equal(
            oldLPShortTokenBalance.add(amount),
          );
          expect(newLPFreeLiquidityBalance).to.equal(
            oldLPFreeLiquidityBalance
              .sub(tokenAmount)
              .add(baseCost)
              .sub(apyFee),
          );
        });

        it('adds premium to underwriter TVL and total TVL', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = amount;

          await p.depositLiquidity(
            lp1,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

          await underlying.mint(buyer.address, parseBase('100000'));
          await underlying
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          const { underlyingTVL: oldUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const { blockNumber, events } = await tx.wait();
          const { timestamp } = await ethers.provider.getBlock(blockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFee = maturity
            .sub(ethers.BigNumber.from(timestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.equal(oldUserTVL.add(baseCost).sub(apyFee));
          expect(newTotalTVL).to.equal(oldTotalTVL.add(baseCost).sub(apyFee));
        });

        it('utilizes multiple LP intervals');
      });

      describe('put option', () => {
        it('transfers cost to pool', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          await p.depositLiquidity(
            lp1,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );

          await base.mint(buyer.address, parseBase('100000'));
          await base
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          const oldBuyerBalance = await base.callStatic.balanceOf(
            buyer.address,
          );
          const oldContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );

          const tx = await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const { events } = await tx.wait();
          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const newBuyerBalance = await base.callStatic.balanceOf(
            buyer.address,
          );
          const newContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );

          expect(newBuyerBalance).to.equal(
            oldBuyerBalance.sub(baseCost).sub(feeCost),
          );
          expect(newContractBalance).to.equal(
            oldContractBalance.add(baseCost).add(feeCost),
          );
        });

        it('mints long tokens for buyer and short tokens for underwriter', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = parseBase(formatUnderlying(amount)).mul(
            fixedToNumber(strike64x64),
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await p.depositLiquidity(
            lp1,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

          await base.mint(buyer.address, parseBase('100000'));
          await base
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          const oldBuyerLongTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            longTokenId,
          );
          const oldLPShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldLPFreeLiquidityBalance = await instance.callStatic.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );

          const tx = await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const { blockNumber, events } = await tx.wait();
          const { timestamp } = await ethers.provider.getBlock(blockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFee = maturity
            .sub(ethers.BigNumber.from(timestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newBuyerLongTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            longTokenId,
          );
          const newLPShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const newLPFreeLiquidityBalance = await instance.callStatic.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );

          expect(newBuyerLongTokenBalance).to.equal(
            oldBuyerLongTokenBalance.add(amount),
          );
          expect(newLPShortTokenBalance).to.equal(
            oldLPShortTokenBalance.add(amount),
          );
          expect(newLPFreeLiquidityBalance).to.equal(
            oldLPFreeLiquidityBalance
              .sub(tokenAmount)
              .add(baseCost)
              .sub(apyFee),
          );
        });

        it('adds premium to underwriter TVL and total TVL', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = parseBase(formatUnderlying(amount)).mul(
            fixedToNumber(strike64x64),
          );

          await p.depositLiquidity(
            lp1,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

          await base.mint(buyer.address, parseBase('100000'));
          await base
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          const { baseTVL: oldUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const { blockNumber, events } = await tx.wait();
          const { timestamp } = await ethers.provider.getBlock(blockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFee = maturity
            .sub(ethers.BigNumber.from(timestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.equal(oldUserTVL.add(baseCost).sub(apyFee));
          expect(newTotalTVL).to.equal(oldTotalTVL.add(baseCost).sub(apyFee));
        });

        it('utilizes multiple LP intervals');
      });

      describe('reverts if', () => {
        it('contract size is less than minimum', async () => {
          const isCall = false;
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

          await expect(
            instance
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

        it('maturity is less than 1 day in the future', async () => {
          const isCall = false;
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = (await getMaturity(1)).sub(ethers.constants.One);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            instance
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

        it('maturity is more than 90 days in the future', async () => {
          const isCall = false;
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = await getMaturity(92);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            instance
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('exp > 90 days');
        });

        it('maturity does not corresponding to 8-hour increment', async () => {
          const isCall = false;
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = (await getMaturity(10)).add(3600);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            instance
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('exp must be 8-hour increment');
        });

        it('call option strike price is more than 2x spot price', async () => {
          const isCall = true;
          const multiplier = 2;

          await p.depositLiquidity(owner, parseOption('100', isCall), isCall);
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(2000 * multiplier).add(
            ethers.constants.One,
          );

          await expect(
            instance
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('strike out of range');
        });

        it('put option strike price is more than 1.2x spot price', async () => {
          const isCall = false;
          const multiplier = 1.2;

          await p.depositLiquidity(
            owner,
            parseOption('100000', isCall),
            isCall,
          );
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(2000 * multiplier).add(
            ethers.constants.One,
          );

          await expect(
            instance
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('strike out of range');
        });

        it('call option strike price is less than 0.8x spot price', async () => {
          const isCall = true;
          const multiplier = 0.8;

          await p.depositLiquidity(owner, parseOption('100', isCall), isCall);
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(2000 * multiplier).sub(
            ethers.constants.One,
          );

          await expect(
            instance
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('strike out of range');
        });

        it('put option strike price is less than 0.5x spot price', async () => {
          const isCall = false;
          const multiplier = 0.5;

          await p.depositLiquidity(
            owner,
            parseOption('100000', isCall),
            isCall,
          );
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(2000 * multiplier).sub(
            ethers.constants.One,
          );

          await expect(
            instance
              .connect(buyer)
              .purchase(
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
                parseOption('100', isCall),
              ),
          ).to.be.revertedWith('strike out of range');
        });

        it('cost is above max cost', async () => {
          const isCall = false;
          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

          await p
            .getToken(isCall)
            .mint(buyer.address, parseOption('100', isCall));
          await p
            .getToken(isCall)
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          await expect(
            instance
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
      });
    });

    describe('#swapAndPurchase', function () {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('should successfully swaps tokens and purchase an option', async () => {
            const pairBase = await createUniswapPair(
              owner,
              uniswap.factory,
              p.base.address,
              uniswap.weth.address,
            );

            const pairUnderlying = await createUniswapPair(
              owner,
              uniswap.factory,
              p.underlying.address,
              uniswap.weth.address,
            );

            await depositUniswapLiquidity(
              lp2,
              uniswap.weth.address,
              pairBase,
              (await pairBase.token0()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100000', DECIMALS_BASE),
              (await pairBase.token1()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100000', DECIMALS_BASE),
            );

            await depositUniswapLiquidity(
              lp2,
              uniswap.weth.address,
              pairUnderlying,
              (await pairUnderlying.token0()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100', DECIMALS_UNDERLYING),
              (await pairUnderlying.token1()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100', DECIMALS_UNDERLYING),
            );

            await p.depositLiquidity(
              lp1,
              parseOption(isCall ? '100' : '100000', isCall),
              isCall,
            );

            const maturity = await getMaturity(10);
            const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

            const purchaseAmountNb = 10;
            const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

            const quote = await instance.quote(
              buyer.address,
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
            );

            const mintAmount = parseOption(!isCall ? '1' : '10000', !isCall);

            await p.getToken(!isCall).mint(buyer.address, mintAmount);
            await p
              .getToken(isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);
            await p
              .getToken(!isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);

            const tx = await instance
              .connect(buyer)
              .swapAndPurchase(
                maturity,
                strike64x64,
                purchaseAmount,
                isCall,
                getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
                getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
                ethers.utils.parseEther('10000'),
                isCall
                  ? [p.base.address, uniswap.weth.address, p.underlying.address]
                  : [
                      p.underlying.address,
                      uniswap.weth.address,
                      p.base.address,
                    ],
                false,
              );

            const { blockNumber } = await tx.wait();
            const { timestamp } = await ethers.provider.getBlock(blockNumber);

            const newBalance = await p
              .getToken(isCall)
              .balanceOf(buyer.address);

            expect(bnToNumber(newBalance, getTokenDecimals(isCall))).to.almost(
              Number(
                formatOption(
                  getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
                  isCall,
                ),
              ) -
                fixedToNumber(quote.baseCost64x64) -
                fixedToNumber(quote.feeCost64x64),
            );

            const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

            if (isCall) {
              const apyFee =
                (purchaseAmountNb *
                  (maturity.toNumber() - timestamp) *
                  FEE_APY) /
                ONE_YEAR;

              expect(
                bnToNumber(
                  await instance.balanceOf(
                    lp1.address,
                    getFreeLiqTokenId(isCall),
                  ),
                  DECIMALS_UNDERLYING,
                ),
              ).to.almost(
                100 -
                  purchaseAmountNb +
                  fixedToNumber(quote.baseCost64x64) -
                  apyFee,
              );
            } else {
              const apyFee =
                (purchaseAmountNb *
                  getStrike(isCall, 2000) *
                  (maturity.toNumber() - timestamp) *
                  FEE_APY) /
                ONE_YEAR;

              expect(
                bnToNumber(
                  await instance.balanceOf(
                    lp1.address,
                    getFreeLiqTokenId(isCall),
                  ),
                  DECIMALS_BASE,
                ),
              ).to.almost(
                100000 -
                  purchaseAmountNb * getStrike(isCall, 2000) +
                  fixedToNumber(quote.baseCost64x64) -
                  apyFee,
              );
            }

            expect(
              bnToNumber(
                await instance.balanceOf(
                  feeReceiver.address,
                  getReservedLiqTokenId(isCall),
                ),
              ),
            ).to.almost(fixedToNumber(quote.feeCost64x64));

            expect(await instance.balanceOf(lp1.address, tokenId.long)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp1.address, tokenId.short)).to.eq(
              purchaseAmount,
            );

            expect(await instance.balanceOf(buyer.address, tokenId.long)).to.eq(
              purchaseAmount,
            );
            expect(
              await instance.balanceOf(buyer.address, tokenId.short),
            ).to.eq(0);
          });

          it('should successfully swaps tokens and purchase an option with ETH', async () => {
            const pairBase = await createUniswapPair(
              owner,
              uniswap.factory,
              p.base.address,
              uniswap.weth.address,
            );

            const pairUnderlying = await createUniswapPair(
              owner,
              uniswap.factory,
              p.underlying.address,
              uniswap.weth.address,
            );

            await depositUniswapLiquidity(
              lp2,
              uniswap.weth.address,
              pairBase,
              (await pairBase.token0()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100000', DECIMALS_BASE),
              (await pairBase.token1()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100000', DECIMALS_BASE),
            );

            await depositUniswapLiquidity(
              lp2,
              uniswap.weth.address,
              pairUnderlying,
              (await pairUnderlying.token0()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100', DECIMALS_UNDERLYING),
              (await pairUnderlying.token1()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100', DECIMALS_UNDERLYING),
            );

            await p.depositLiquidity(
              lp1,
              parseOption(isCall ? '100' : '100000', isCall),
              isCall,
            );

            const maturity = await getMaturity(10);
            const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

            const purchaseAmountNb = 10;
            const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

            const quote = await instance.quote(
              buyer.address,
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
            );

            const mintAmount = parseOption(!isCall ? '1' : '10000', !isCall);

            await p.getToken(!isCall).mint(buyer.address, mintAmount);
            await p
              .getToken(isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);
            await p
              .getToken(!isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);

            const tx = await instance
              .connect(buyer)
              .swapAndPurchase(
                maturity,
                strike64x64,
                purchaseAmount,
                isCall,
                getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
                getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
                0,
                isCall
                  ? [uniswap.weth.address, p.underlying.address]
                  : [uniswap.weth.address, p.base.address],
                false,
                { value: ethers.utils.parseEther('2') },
              );

            const { blockNumber } = await tx.wait();
            const { timestamp } = await ethers.provider.getBlock(blockNumber);

            const newBalance = await p
              .getToken(isCall)
              .balanceOf(buyer.address);

            expect(bnToNumber(newBalance, getTokenDecimals(isCall))).to.almost(
              Number(
                formatOption(
                  getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
                  isCall,
                ),
              ) -
                fixedToNumber(quote.baseCost64x64) -
                fixedToNumber(quote.feeCost64x64),
            );

            const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

            if (isCall) {
              const apyFee =
                (purchaseAmountNb *
                  (maturity.toNumber() - timestamp) *
                  FEE_APY) /
                ONE_YEAR;

              expect(
                bnToNumber(
                  await instance.balanceOf(
                    lp1.address,
                    getFreeLiqTokenId(isCall),
                  ),
                  DECIMALS_UNDERLYING,
                ),
              ).to.almost(
                100 -
                  purchaseAmountNb +
                  fixedToNumber(quote.baseCost64x64) -
                  apyFee,
              );
            } else {
              const apyFee =
                (purchaseAmountNb *
                  getStrike(isCall, 2000) *
                  (maturity.toNumber() - timestamp) *
                  FEE_APY) /
                ONE_YEAR;

              expect(
                bnToNumber(
                  await instance.balanceOf(
                    lp1.address,
                    getFreeLiqTokenId(isCall),
                  ),
                  DECIMALS_BASE,
                ),
              ).to.almost(
                100000 -
                  purchaseAmountNb * getStrike(isCall, 2000) +
                  fixedToNumber(quote.baseCost64x64) -
                  apyFee,
              );
            }

            expect(
              bnToNumber(
                await instance.balanceOf(
                  feeReceiver.address,
                  getReservedLiqTokenId(isCall),
                ),
              ),
            ).to.almost(fixedToNumber(quote.feeCost64x64));

            expect(await instance.balanceOf(lp1.address, tokenId.long)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp1.address, tokenId.short)).to.eq(
              purchaseAmount,
            );

            expect(await instance.balanceOf(buyer.address, tokenId.long)).to.eq(
              purchaseAmount,
            );
            expect(
              await instance.balanceOf(buyer.address, tokenId.short),
            ).to.eq(0);
          });

          it('should successfully swaps tokens and purchase an option without dust left', async () => {
            const pairBase = await createUniswapPair(
              owner,
              uniswap.factory,
              p.base.address,
              uniswap.weth.address,
            );

            const pairUnderlying = await createUniswapPair(
              owner,
              uniswap.factory,
              p.underlying.address,
              uniswap.weth.address,
            );

            await depositUniswapLiquidity(
              lp2,
              uniswap.weth.address,
              pairBase,
              (await pairBase.token0()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100000', DECIMALS_BASE),
              (await pairBase.token1()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100000', DECIMALS_BASE),
            );

            await depositUniswapLiquidity(
              lp2,
              uniswap.weth.address,
              pairUnderlying,
              (await pairUnderlying.token0()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100', DECIMALS_UNDERLYING),
              (await pairUnderlying.token1()) === uniswap.weth.address
                ? ethers.utils.parseUnits('100', 18)
                : ethers.utils.parseUnits('100', DECIMALS_UNDERLYING),
            );

            await p.depositLiquidity(
              lp1,
              parseOption(isCall ? '100' : '100000', isCall),
              isCall,
            );

            const maturity = await getMaturity(10);
            const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

            const purchaseAmountNb = 10;
            const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

            const quote = await instance.quote(
              buyer.address,
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
            );

            const mintAmount = parseOption(!isCall ? '1' : '10000', !isCall);

            await p.getToken(!isCall).mint(buyer.address, mintAmount);
            await p
              .getToken(isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);
            await p
              .getToken(!isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);

            const tx = await instance
              .connect(buyer)
              .swapAndPurchase(
                maturity,
                strike64x64,
                purchaseAmount,
                isCall,
                getMaxCost(quote.baseCost64x64, quote.feeCost64x64, isCall),
                '0',
                ethers.utils.parseEther('10000'),
                isCall
                  ? [p.base.address, uniswap.weth.address, p.underlying.address]
                  : [
                      p.underlying.address,
                      uniswap.weth.address,
                      p.base.address,
                    ],
                false,
              );

            const { blockNumber } = await tx.wait();
            const { timestamp } = await ethers.provider.getBlock(blockNumber);

            const newBalance = await p
              .getToken(isCall)
              .balanceOf(buyer.address);

            expect(bnToNumber(newBalance, getTokenDecimals(isCall))).to.almost(
              0,
            );

            const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

            if (isCall) {
              const apyFee =
                (purchaseAmountNb *
                  (maturity.toNumber() - timestamp) *
                  FEE_APY) /
                ONE_YEAR;

              expect(
                bnToNumber(
                  await instance.balanceOf(
                    lp1.address,
                    getFreeLiqTokenId(isCall),
                  ),
                  DECIMALS_UNDERLYING,
                ),
              ).to.almost(
                100 -
                  purchaseAmountNb +
                  fixedToNumber(quote.baseCost64x64) -
                  apyFee,
              );
            } else {
              const apyFee =
                (purchaseAmountNb *
                  getStrike(isCall, 2000) *
                  (maturity.toNumber() - timestamp) *
                  FEE_APY) /
                ONE_YEAR;

              expect(
                bnToNumber(
                  await instance.balanceOf(
                    lp1.address,
                    getFreeLiqTokenId(isCall),
                  ),
                  DECIMALS_BASE,
                ),
              ).to.almost(
                100000 -
                  purchaseAmountNb * getStrike(isCall, 2000) +
                  fixedToNumber(quote.baseCost64x64) -
                  apyFee,
              );
            }

            expect(
              bnToNumber(
                await instance.balanceOf(
                  feeReceiver.address,
                  getReservedLiqTokenId(isCall),
                ),
              ),
            ).to.almost(fixedToNumber(quote.feeCost64x64));

            expect(await instance.balanceOf(lp1.address, tokenId.long)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp1.address, tokenId.short)).to.eq(
              purchaseAmount,
            );

            expect(await instance.balanceOf(buyer.address, tokenId.long)).to.eq(
              purchaseAmount,
            );
            expect(
              await instance.balanceOf(buyer.address, tokenId.short),
            ).to.eq(0);
          });
        });
      }
    });

    describe('#writeFrom', () => {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('should successfully manually underwrite an option without use of an external operator', async () => {
            const maturity = await getMaturity(30);
            const strike64x64 = fixedFromFloat(2);
            const amount = parseUnderlying('1');

            const token = isCall ? underlying : base;
            let toMint = isCall ? parseUnderlying('1') : parseBase('2');

            // mint extra to account for APY fee
            toMint = toMint.mul(ethers.constants.Two);

            await token.mint(lp1.address, toMint);
            await token
              .connect(lp1)
              .approve(instance.address, ethers.constants.MaxUint256);

            await instance
              .connect(lp1)
              .writeFrom(
                lp1.address,
                lp2.address,
                maturity,
                strike64x64,
                amount,
                isCall,
              );

            const tokenIds = getOptionTokenIds(
              await getMaturity(30),
              fixedFromFloat(2),
              isCall,
            );

            // TODO: test changeTokenBalance
            // expect(await p.getToken(isCall).balanceOf(lp1.address)).to.eq(0);
            expect(await instance.balanceOf(lp1.address, tokenIds.long)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp2.address, tokenIds.long)).to.eq(
              amount,
            );
            expect(await instance.balanceOf(lp1.address, tokenIds.short)).to.eq(
              amount,
            );
            expect(await instance.balanceOf(lp2.address, tokenIds.short)).to.eq(
              0,
            );
          });

          it('should successfully manually underwrite an option with use of an external operator', async () => {
            const maturity = await getMaturity(30);
            const strike64x64 = fixedFromFloat(2);
            const amount = parseUnderlying('1');

            const token = isCall ? underlying : base;
            let toMint = isCall ? parseUnderlying('1') : parseBase('2');

            // mint extra to account for APY fee
            toMint = toMint.mul(ethers.constants.Two);

            await token.mint(lp1.address, toMint);
            await token
              .connect(lp1)
              .approve(instance.address, ethers.constants.MaxUint256);

            await instance.connect(lp1).setApprovalForAll(owner.address, true);

            await instance
              .connect(owner)
              .writeFrom(
                lp1.address,
                lp2.address,
                maturity,
                strike64x64,
                amount,
                isCall,
              );

            const tokenIds = getOptionTokenIds(
              await getMaturity(30),
              fixedFromFloat(2),
              isCall,
            );

            // TODO: test changeTokenBalance
            // expect(await p.getToken(isCall).balanceOf(lp1.address)).to.eq(0);
            expect(await instance.balanceOf(lp1.address, tokenIds.long)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp2.address, tokenIds.long)).to.eq(
              amount,
            );
            expect(await instance.balanceOf(lp1.address, tokenIds.short)).to.eq(
              amount,
            );
            expect(await instance.balanceOf(lp2.address, tokenIds.short)).to.eq(
              0,
            );
          });
        });
      }

      describe('reverts if', () => {
        it('operator is not approved', async () => {
          await expect(
            instance
              .connect(owner)
              .writeFrom(
                lp1.address,
                lp2.address,
                ethers.constants.Zero,
                ethers.constants.Zero,
                ethers.constants.Zero,
                false,
              ),
          ).to.be.revertedWith('not approved');
        });
      });
    });

    describe('#update', () => {
      it('todo');
    });
  });
}
