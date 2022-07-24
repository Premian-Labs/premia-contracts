import { ethers } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, IExchangeHelper, IPool } from '../../typechain';
import { BigNumber, BigNumberish } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  fixedFromFloat,
  fixedToBn,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
} from '@premia/utils';

import { IUniswap, uniswapABIs } from '../../test/utils/uniswap';

import {
  formatUnderlying,
  getFreeLiqTokenId,
  getLong,
  getMaturity,
  getMinPrice,
  getReservedLiqTokenId,
  getShort,
  getStrike,
  getTokenDecimals,
  ONE_YEAR,
  parseBase,
  parseOption,
  parseUnderlying,
  PoolUtil,
} from '../../test/pool/PoolUtil';

interface PoolWriteBehaviorArgs {
  deploy: () => Promise<IPool>;
  getBase: () => Promise<ERC20Mock>;
  getUnderlying: () => Promise<ERC20Mock>;
  getPoolUtil: () => Promise<PoolUtil>;
  apyFeeRate: BigNumberish;
  getUniswap: () => Promise<IUniswap>;
  getExchangeHelper: () => Promise<IExchangeHelper>;
}

export function describeBehaviorOfPoolWrite({
  deploy,
  getBase,
  getUnderlying,
  getPoolUtil,
  apyFeeRate,
  getUniswap,
  getExchangeHelper,
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
    let exchangeHelper: IExchangeHelper;

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
      exchangeHelper = await getExchangeHelper();
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

          expect(fixedToNumber(q.baseCost64x64) * 2000).to.almost(40.6);
          expect(fixedToNumber(q.feeCost64x64)).to.almost.eq(
            fixedToNumber(q.baseCost64x64) * 0.01,
          );
          expect(fixedToNumber(q.cLevel64x64)).to.almost(3);
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
          const maturity = timestamp + 24 * 3600 + 1;

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

        it('accounts for spot price adjustment', async () => {
          const isCall = true;

          // set offset to 1%
          await instance
            .connect(owner)
            .setSpotOffset64x64(ethers.BigNumber.from('0x28f5c28f5c28f5c'));

          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          await instance
            .connect(owner)
            .setCLevel64x64(fixedFromFloat('0.1'), isCall);

          const maturity = await getMaturity(5);
          const strike64x64 = fixedFromFloat(getStrike(!isCall, 2000 * 1.01));
          const purchaseAmountNb = 10;
          const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

          const quote = await instance.callStatic.quote(
            buyer.address,
            maturity,
            strike64x64,
            purchaseAmount,
            isCall,
          );

          const spot64x64 = fixedFromFloat(2000 * 1.01);

          expect(strike64x64).to.be.lt(spot64x64);

          const intrinsicValue64x64 = spot64x64
            .sub(strike64x64)
            .mul(BigNumber.from(purchaseAmountNb))
            .div(BigNumber.from(2000 * 1.01));

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

          expect(fixedToNumber(q.baseCost64x64)).to.almost(74.43);
          expect(fixedToNumber(q.feeCost64x64)).to.almost.eq(
            fixedToNumber(q.baseCost64x64) * 0.03,
          );
          expect(fixedToNumber(q.cLevel64x64)).to.almost(3.24);
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
          const maturity = timestamp + 24 * 3600 + 1;

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

        it('accounts for spot price adjustment', async () => {
          const isCall = false;

          // set offset to 1%
          await instance
            .connect(owner)
            .setSpotOffset64x64(ethers.BigNumber.from('0x28f5c28f5c28f5c'));

          await p.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          await instance
            .connect(owner)
            .setCLevel64x64(fixedFromFloat('0.1'), isCall);

          const maturity = await getMaturity(5);
          const strike64x64 = fixedFromFloat(getStrike(!isCall, 2000 * 0.99));
          const purchaseAmountNb = 5;
          const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

          const quote = await instance.callStatic.quote(
            buyer.address,
            maturity,
            strike64x64,
            purchaseAmount,
            isCall,
          );

          const spot64x64 = fixedFromFloat(2000 * 0.99);

          expect(strike64x64).to.be.gt(spot64x64);

          const intrinsicValue64x64 = strike64x64
            .sub(spot64x64)
            .mul(BigNumber.from(purchaseAmountNb));

          expect(fixedToNumber(quote.baseCost64x64)).to.almost(
            fixedToNumber(intrinsicValue64x64) +
              (await getMinPrice(
                purchaseAmountNb * getStrike(!isCall, 2000 * 0.99),
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
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
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
          expect(newLPFreeLiquidityBalance).to.be.closeTo(
            oldLPFreeLiquidityBalance
              .sub(tokenAmount)
              .add(baseCost)
              .sub(apyFee),
            1,
          );
        });

        it('processes underwriter divestment', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = amount;

          const divestedLiquidity = tokenAmount.mul(17n);

          await p.depositLiquidity(lp1, divestedLiquidity, isCall);

          const { timestamp: depositTimestamp } =
            await ethers.provider.getBlock('latest');

          await instance
            .connect(lp1)
            .setDivestmentTimestamp(depositTimestamp + 24 * 3600, isCall);

          await ethers.provider.send('evm_setNextBlockTimestamp', [
            depositTimestamp + 24 * 3600,
          ]);

          await p.depositLiquidity(
            lp2,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

          const oldFreeLiquidityBalance = await instance.callStatic.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );
          const oldReservedLiquidityBalance =
            await instance.callStatic.balanceOf(
              lp1.address,
              getReservedLiqTokenId(isCall),
            );

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const newFreeLiquidityBalance = await instance.callStatic.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );
          const newReservedLiquidityBalance =
            await instance.callStatic.balanceOf(
              lp1.address,
              getReservedLiqTokenId(isCall),
            );

          expect(newFreeLiquidityBalance).to.equal(
            oldFreeLiquidityBalance.sub(divestedLiquidity),
          );
          expect(newReservedLiquidityBalance).to.equal(
            oldReservedLiquidityBalance.add(divestedLiquidity),
          );
        });

        it('avoids matching buyer to own liquidity', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = amount;

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await p.depositLiquidity(
            buyer,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );
          await p.depositLiquidity(
            lp1,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

          const { liquidityBeforePosition: buyerPosition } =
            await instance.callStatic.getLiquidityQueuePosition(
              buyer.address,
              isCall,
            );
          const { liquidityBeforePosition: lpPosition } =
            await instance.callStatic.getLiquidityQueuePosition(
              lp1.address,
              isCall,
            );

          expect(buyerPosition).to.be.lt(lpPosition);

          const oldBuyerShortTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            shortTokenId,
          );
          const oldLPShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const newBuyerShortTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            shortTokenId,
          );
          const newLPShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          expect(newBuyerShortTokenBalance).to.equal(oldBuyerShortTokenBalance);
          expect(newLPShortTokenBalance).to.equal(
            oldLPShortTokenBalance.add(amount),
          );
        });

        it('updates underwriter TVL', async () => {
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
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.be.closeTo(
            oldUserTVL.add(baseCost).sub(apyFee),
            1,
          );
          expect(newTotalTVL).to.be.closeTo(
            oldTotalTVL.add(baseCost).sub(apyFee),
            1,
          );
        });

        it('updates divesting user TVL', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = amount;

          const divestedLiquidity = tokenAmount.mul(17n);

          await p.depositLiquidity(lp1, divestedLiquidity, isCall);

          const { timestamp: depositTimestamp } =
            await ethers.provider.getBlock('latest');

          await instance
            .connect(lp1)
            .setDivestmentTimestamp(depositTimestamp + 24 * 3600, isCall);

          await ethers.provider.send('evm_setNextBlockTimestamp', [
            depositTimestamp + 24 * 3600,
          ]);

          await p.depositLiquidity(
            lp2,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

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
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.equal(oldUserTVL.sub(divestedLiquidity));
          expect(newTotalTVL).to.equal(
            oldTotalTVL.add(baseCost).sub(apyFee).sub(divestedLiquidity),
          );
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
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
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
          expect(newLPFreeLiquidityBalance).to.be.closeTo(
            oldLPFreeLiquidityBalance
              .sub(tokenAmount)
              .add(baseCost)
              .sub(apyFee),
            1,
          );
        });

        it('processes underwriter divestment', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = parseBase(formatUnderlying(amount)).mul(
            fixedToNumber(strike64x64),
          );

          const divestedLiquidity = tokenAmount.mul(17n);

          await p.depositLiquidity(lp1, divestedLiquidity, isCall);

          const { timestamp: depositTimestamp } =
            await ethers.provider.getBlock('latest');

          await instance
            .connect(lp1)
            .setDivestmentTimestamp(depositTimestamp + 24 * 3600, isCall);

          await ethers.provider.send('evm_setNextBlockTimestamp', [
            depositTimestamp + 24 * 3600,
          ]);

          await p.depositLiquidity(
            lp2,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

          const oldFreeLiquidityBalance = await instance.callStatic.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );
          const oldReservedLiquidityBalance =
            await instance.callStatic.balanceOf(
              lp1.address,
              getReservedLiqTokenId(isCall),
            );

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const newFreeLiquidityBalance = await instance.callStatic.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );
          const newReservedLiquidityBalance =
            await instance.callStatic.balanceOf(
              lp1.address,
              getReservedLiqTokenId(isCall),
            );

          expect(newFreeLiquidityBalance).to.equal(
            oldFreeLiquidityBalance.sub(divestedLiquidity),
          );
          expect(newReservedLiquidityBalance).to.equal(
            oldReservedLiquidityBalance.add(divestedLiquidity),
          );
        });

        it('avoids matching buyer to own liquidity', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = parseBase(formatUnderlying(amount)).mul(
            fixedToNumber(strike64x64),
          );

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await p.depositLiquidity(
            buyer,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );
          await p.depositLiquidity(
            lp1,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

          const { liquidityBeforePosition: buyerPosition } =
            await instance.callStatic.getLiquidityQueuePosition(
              buyer.address,
              isCall,
            );
          const { liquidityBeforePosition: lpPosition } =
            await instance.callStatic.getLiquidityQueuePosition(
              lp1.address,
              isCall,
            );

          expect(buyerPosition).to.be.lt(lpPosition);

          const oldBuyerShortTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            shortTokenId,
          );
          const oldLPShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const newBuyerShortTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            shortTokenId,
          );
          const newLPShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          expect(newBuyerShortTokenBalance).to.equal(oldBuyerShortTokenBalance);
          expect(newLPShortTokenBalance).to.equal(
            oldLPShortTokenBalance.add(amount),
          );
        });

        it('updates underwriter TVL', async () => {
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
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.be.closeTo(
            oldUserTVL.add(baseCost).sub(apyFee),
            1,
          );
          expect(newTotalTVL).to.be.closeTo(
            oldTotalTVL.add(baseCost).sub(apyFee),
            1,
          );
        });

        it('updates divesting user TVL', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const tokenAmount = parseBase(formatUnderlying(amount)).mul(
            fixedToNumber(strike64x64),
          );

          const divestedLiquidity = tokenAmount.mul(17n);

          await p.depositLiquidity(lp1, divestedLiquidity, isCall);

          const { timestamp: depositTimestamp } =
            await ethers.provider.getBlock('latest');

          await instance
            .connect(lp1)
            .setDivestmentTimestamp(depositTimestamp + 24 * 3600, isCall);

          await ethers.provider.send('evm_setNextBlockTimestamp', [
            depositTimestamp + 24 * 3600,
          ]);

          await p.depositLiquidity(
            lp2,
            tokenAmount.mul(ethers.constants.Two),
            isCall,
          );

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
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.equal(oldUserTVL.sub(divestedLiquidity));
          expect(newTotalTVL).to.be.closeTo(
            oldTotalTVL.add(baseCost).sub(apyFee).sub(divestedLiquidity),
            1,
          );
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
          it('executes purchase using non-pool ERC20 token', async () => {
            await p.depositLiquidity(
              lp1,
              parseOption(isCall ? '100' : '100000', isCall),
              isCall,
            );

            const maturity = await getMaturity(10);
            const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

            // amount of option to buy
            const purchaseAmount = parseUnderlying('1');

            const { baseCost64x64, feeCost64x64 } = await instance.quote(
              buyer.address,
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
            );
            const expectedCostPoolToken = fixedToBn(
              baseCost64x64.add(feeCost64x64),
              getTokenDecimals(isCall),
            );
            const uniswapPath = isCall
              ? [base.address, uniswap.weth.address, underlying.address]
              : [underlying.address, uniswap.weth.address, base.address];

            // how much needed to get expected cost
            const [expectedInputAmount] = await uniswap.router.getAmountsIn(
              expectedCostPoolToken,
              uniswapPath,
            );
            // input as 120% of price.
            const swapMaxTokenIn = expectedInputAmount.mul(120).div(100);

            // amount out from the swap, we can set to 0 because the tx will revert if the amount is not enough to purchase
            // const swapMinTokenOut = 0

            const longTokenId = formatTokenId({
              tokenType: getLong(isCall),
              maturity,
              strike64x64,
            });

            const oldNonPoolTokenBalance = await (isCall
              ? base
              : underlying
            ).balanceOf(buyer.address);

            const oldLongTokenBalance = await instance.balanceOf(
              buyer.address,
              longTokenId,
            );

            const tokenIn = isCall ? p.base.address : p.underlying.address;

            const { timestamp } = await ethers.provider.getBlock('latest');

            const iface = new ethers.utils.Interface(uniswapABIs);
            // pull exact token from user, => swap for pool token => purchase, additional pool token will be refunded
            const data = iface.encodeFunctionData('swapExactTokensForTokens', [
              swapMaxTokenIn,
              expectedCostPoolToken,
              uniswapPath,
              exchangeHelper.address,
              timestamp + 86400,
            ]);

            await instance.connect(buyer).swapAndPurchase(
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
              tokenIn,
              swapMaxTokenIn,
              0, // how much to take out from swap. Uniswap will assert it
              uniswap.router.address, // exchange to trade on
              data,
              buyer.address,
            );

            const newNonPoolTokenBalance = await (isCall
              ? base
              : underlying
            ).callStatic.balanceOf(buyer.address);

            const newLongTokenBalance = await instance.balanceOf(
              buyer.address,
              longTokenId,
            );

            expect(newNonPoolTokenBalance).to.be.closeTo(
              oldNonPoolTokenBalance.sub(swapMaxTokenIn),
              1,
            );

            // TODO: assert cost
            expect(newLongTokenBalance).to.be.closeTo(
              oldLongTokenBalance.add(purchaseAmount),
              1,
            );
          });

          it('executes purchase using ETH', async () => {
            await p.depositLiquidity(
              lp1,
              parseOption(isCall ? '100' : '100000', isCall),
              isCall,
            );

            const maturity = await getMaturity(10);
            const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

            const longTokenId = formatTokenId({
              tokenType: getLong(isCall),
              maturity,
              strike64x64,
            });

            // amount of option to buy
            const purchaseAmount = parseUnderlying('1');

            const { baseCost64x64, feeCost64x64 } = await instance.quote(
              buyer.address,
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
            );
            const expectedCostPoolToken = fixedToBn(
              baseCost64x64.add(feeCost64x64),
              getTokenDecimals(isCall),
            );

            // mock exchange swap data.
            const uniswapPath = isCall
              ? [uniswap.weth.address, underlying.address]
              : [uniswap.weth.address, base.address];

            // how much needed to get expected cost
            const [expectedInputAmount] = await uniswap.router.getAmountsIn(
              expectedCostPoolToken,
              uniswapPath,
            );

            // input as 120% of price.
            const maxEthToPay = expectedInputAmount.mul(120).div(100);

            const oldLongTokenBalance = await instance.balanceOf(
              buyer.address,
              longTokenId,
            );

            const { timestamp } = await ethers.provider.getBlock('latest');

            const iface = new ethers.utils.Interface(uniswapABIs);

            // eth will be wrap into weth, so we call uniswap to trade weth to pool token
            const data = iface.encodeFunctionData('swapTokensForExactTokens', [
              expectedCostPoolToken,
              maxEthToPay,
              uniswapPath,
              exchangeHelper.address,
              timestamp + 86400,
            ]);

            await instance.connect(buyer).swapAndPurchase(
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
              uniswap.weth.address, // tokenIn
              0,
              0,
              uniswap.router.address, // exchange to trade on
              data,
              buyer.address,
              { value: maxEthToPay },
            );

            const newLongTokenBalance = await instance.balanceOf(
              buyer.address,
              longTokenId,
            );

            expect(newLongTokenBalance).to.be.closeTo(
              oldLongTokenBalance.add(purchaseAmount),
              1,
            );
          });

          it('executes purchase with ETH and weth', async () => {
            // only for put pool
            if (isCall) return;

            await p.depositLiquidity(
              lp1,
              parseOption('100000', isCall),
              isCall,
            );

            const maturity = await getMaturity(10);
            const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

            const longTokenId = formatTokenId({
              tokenType: getLong(isCall),
              maturity,
              strike64x64,
            });

            // amount of option to buy
            const purchaseAmount = parseUnderlying('1');

            const { baseCost64x64, feeCost64x64 } = await instance.quote(
              buyer.address,
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
            );
            const expectedCostPoolToken = fixedToBn(
              baseCost64x64.add(feeCost64x64),
              getTokenDecimals(isCall),
            );

            const uniswapPath = [uniswap.weth.address, base.address];

            // how much needed to get expected cost
            const [expectedInputAmount] = await uniswap.router.getAmountsIn(
              expectedCostPoolToken,
              uniswapPath,
            );

            // const totalEthToPay = expectedInputAmount;
            const ethToPay = expectedInputAmount.div(2);
            const wethToPay = expectedInputAmount.sub(ethToPay);

            await uniswap.weth.connect(buyer).deposit({ value: wethToPay });
            await uniswap.weth
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);

            const oldLongTokenBalance = await instance.balanceOf(
              buyer.address,
              longTokenId,
            );

            const { timestamp } = await ethers.provider.getBlock('latest');

            const iface = new ethers.utils.Interface(uniswapABIs);

            // eth will be wrap into weth, so we call uniswap to trade weth to pool token, with amount = msg.value + maxTokenIn
            const data = iface.encodeFunctionData('swapTokensForExactTokens', [
              expectedCostPoolToken,
              expectedInputAmount,
              uniswapPath,
              exchangeHelper.address,
              timestamp + 86400,
            ]);

            await instance.connect(buyer).swapAndPurchase(
              maturity,
              strike64x64,
              purchaseAmount,
              isCall,
              uniswap.weth.address, // tokenIn
              wethToPay,
              expectedCostPoolToken,
              uniswap.router.address, // exchange to trade on
              data,
              buyer.address,
              { value: ethToPay },
            );

            const nonPoolTokenAfter = await uniswap.weth.balanceOf(
              buyer.address,
            );
            const newLongTokenBalance = await instance.balanceOf(
              buyer.address,
              longTokenId,
            );

            // all weth were spent and swapped to dai.
            expect(nonPoolTokenAfter.eq(0)).to.be.true;

            expect(newLongTokenBalance).to.be.closeTo(
              oldLongTokenBalance.add(purchaseAmount),
              1,
            );
          });
        });
      }
    });

    describe('#writeFrom', () => {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('should successfully manually underwrite an option without use of an external operator', async () => {
            const maturity = await getMaturity(30);
            const strike = getStrike(isCall, 2000);
            const strike64x64 = fixedFromFloat(strike);
            const amount = parseUnderlying('1');

            const token = isCall ? underlying : base;

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
              strike64x64,
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
            const strike = getStrike(isCall, 2000);
            const strike64x64 = fixedFromFloat(strike);
            const amount = parseUnderlying('1');

            const token = isCall ? underlying : base;

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
              strike64x64,
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

        it('maturity is less than 1 day in the future', async () => {
          const isCall = false;
          const maturity = (await getMaturity(1)).sub(ethers.constants.One);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            instance
              .connect(lp1)
              .writeFrom(
                lp1.address,
                lp1.address,
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
              ),
          ).to.be.revertedWith('exp < 1 day');
        });

        it('maturity is more than 90 days in the future', async () => {
          const isCall = false;
          const maturity = await getMaturity(92);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            instance
              .connect(lp1)
              .writeFrom(
                lp1.address,
                lp1.address,
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
              ),
          ).to.be.revertedWith('exp > 90 days');
        });

        it('maturity does not corresponding to 8-hour increment', async () => {
          const isCall = false;
          const maturity = (await getMaturity(10)).add(3600);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            instance
              .connect(lp1)
              .writeFrom(
                lp1.address,
                lp1.address,
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
              ),
          ).to.be.revertedWith('exp must be 8-hour increment');
        });

        it('call option strike price is more than 2x spot price', async () => {
          const isCall = true;
          const multiplier = 2;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(2000 * multiplier).add(
            ethers.constants.One,
          );

          await expect(
            instance
              .connect(lp1)
              .writeFrom(
                lp1.address,
                lp1.address,
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
              ),
          ).to.be.revertedWith('strike out of range');
        });

        it('put option strike price is more than 1.2x spot price', async () => {
          const isCall = false;
          const multiplier = 1.2;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(2000 * multiplier).add(
            ethers.constants.One,
          );

          await expect(
            instance
              .connect(lp1)
              .writeFrom(
                lp1.address,
                lp1.address,
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
              ),
          ).to.be.revertedWith('strike out of range');
        });

        it('call option strike price is less than 0.8x spot price', async () => {
          const isCall = true;
          const multiplier = 0.8;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(2000 * multiplier).sub(
            ethers.constants.One,
          );

          await expect(
            instance
              .connect(lp1)
              .writeFrom(
                lp1.address,
                lp1.address,
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
              ),
          ).to.be.revertedWith('strike out of range');
        });

        it('put option strike price is less than 0.5x spot price', async () => {
          const isCall = false;
          const multiplier = 0.5;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(2000 * multiplier).sub(
            ethers.constants.One,
          );

          await expect(
            instance
              .connect(lp1)
              .writeFrom(
                lp1.address,
                lp1.address,
                maturity,
                strike64x64,
                parseUnderlying('1'),
                isCall,
              ),
          ).to.be.revertedWith('strike out of range');
        });
      });
    });

    describe('#update', () => {
      it('todo');
    });
  });
}
