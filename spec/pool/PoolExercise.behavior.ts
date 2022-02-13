import { ethers } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, FeeDiscount, IPool } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
} from '@premia/utils';

import {
  formatOption,
  formatUnderlying,
  getExerciseValue,
  parseBase,
  parseUnderlying,
  getFreeLiqTokenId,
  getReservedLiqTokenId,
  getShort,
  getLong,
  getStrike,
  getMaturity,
  PoolUtil,
} from '../../test/pool/PoolUtil';
import { createUniswap, IUniswap } from '../../test/utils/uniswap';

interface PoolExerciseBehaviorArgs {
  deploy: () => Promise<IPool>;
  getBase: () => Promise<ERC20Mock>;
  getUnderlying: () => Promise<ERC20Mock>;
  getFeeDiscount: () => Promise<FeeDiscount>;
  getXPremia: () => Promise<ERC20Mock>;
  getPoolUtil: () => Promise<PoolUtil>;
}

const ONE_MONTH = 30 * 24 * 3600;

export function describeBehaviorOfPoolExercise({
  deploy,
  getUnderlying,
  getBase,
  getFeeDiscount,
  getXPremia,
  getPoolUtil,
}: PoolExerciseBehaviorArgs) {
  describe('::PoolExercise', () => {
    let owner: SignerWithAddress;
    let buyer: SignerWithAddress;
    let lp1: SignerWithAddress;
    let lp2: SignerWithAddress;
    let thirdParty: SignerWithAddress;
    // TODO: pass as arg
    let feeReceiver: SignerWithAddress;
    let instance: IPool;
    let base: ERC20Mock;
    let underlying: ERC20Mock;
    let p: PoolUtil;
    let uniswap: IUniswap;

    before(async () => {
      [owner, buyer, lp1, lp2, thirdParty, feeReceiver] =
        await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
      // TODO: don't
      p = await getPoolUtil();
      uniswap = await createUniswap(owner);
      base = await getBase();
      underlying = await getUnderlying();
    });

    describe('#exerciseFrom', function () {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('should successfully exercise', async () => {
            const maturity = await getMaturity(10);
            const strike = getStrike(isCall, 2000);
            const strike64x64 = fixedFromFloat(strike);
            const amountNb = 10;
            const amount = parseUnderlying(amountNb.toString());

            const quote = await p.purchaseOption(
              lp1,
              buyer,
              amount,
              maturity,
              strike64x64,
              isCall,
            );

            const freeLiquidityTokenId = getFreeLiqTokenId(isCall);
            const { long: longTokenId } = getOptionTokenIds(
              maturity,
              strike64x64,
              isCall,
            );

            const price = isCall ? strike * 1.4 : strike * 0.7;
            await p.setUnderlyingPrice(
              ethers.utils.parseUnits(price.toString(), 8),
            );

            const oldBalance = await p
              .getToken(isCall)
              .balanceOf(buyer.address);

            const oldFreeLiquidity = isCall
              ? amount
              : parseBase(formatUnderlying(amount)).mul(
                  fixedToNumber(strike64x64),
                );

            await instance
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
            ).sub(oldBalance);

            expect(Number(formatOption(premium, isCall))).to.almost(
              exerciseValue,
            );

            expect(await instance.balanceOf(buyer.address, longTokenId)).to.eq(
              0,
            );

            const newFreeLiquidity = await instance.balanceOf(
              lp1.address,
              freeLiquidityTokenId,
            );

            // Free liq = initial amount + premia paid
            expect(Number(formatOption(newFreeLiquidity, isCall))).to.almost(
              Number(formatOption(oldFreeLiquidity, isCall)) -
                exerciseValue +
                fixedToNumber(quote.baseCost64x64),
            );
          });

          it('processes eligible option on behalf of given account with approval', async () => {
            const maturity = await getMaturity(10);
            const strike = getStrike(isCall, 2000);
            const strike64x64 = fixedFromFloat(strike);
            const amount = parseUnderlying('1');

            await p.purchaseOption(
              lp1,
              buyer,
              amount,
              maturity,
              strike64x64,
              isCall,
            );

            const longTokenId = formatTokenId({
              tokenType: getLong(isCall),
              maturity,
              strike64x64,
            });

            const price = isCall ? strike * 1.4 : strike * 0.7;
            await p.setUnderlyingPrice(
              ethers.utils.parseUnits(price.toString(), 8),
            );

            await instance
              .connect(buyer)
              .setApprovalForAll(thirdParty.address, true);

            const poolToken = p.getToken(isCall);

            const oldBalanceBuyer = await poolToken.callStatic.balanceOf(
              buyer.address,
            );
            const oldBalanceThirdParty = await poolToken.callStatic.balanceOf(
              thirdParty.address,
            );

            await expect(
              instance
                .connect(thirdParty)
                .exerciseFrom(buyer.address, longTokenId, amount),
            ).not.to.be.reverted;

            const newBalanceBuyer = await poolToken.callStatic.balanceOf(
              buyer.address,
            );
            const newBalanceThirdParty = await poolToken.callStatic.balanceOf(
              thirdParty.address,
            );

            // validate that buyer is beneficiary of transaction
            expect(newBalanceBuyer).to.be.gt(oldBalanceBuyer);
            expect(newBalanceThirdParty).to.equal(oldBalanceThirdParty);
          });
        });
      }

      describe('reverts if', () => {
        it('token is a SHORT token', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));
          const amount = parseUnderlying('1');

          await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            instance
              .connect(buyer)
              .exerciseFrom(buyer.address, shortTokenId, amount),
          ).to.be.revertedWith('invalid type');
        });

        it('sender is not authorized to exercise on behalf of given account', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
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
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            instance
              .connect(thirdParty)
              .exerciseFrom(buyer.address, longTokenId, amount),
          ).to.be.revertedWith('not approved');
        });

        it('option is not ITM', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));
          const amount = parseUnderlying('1');

          await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            instance
              .connect(buyer)
              .exerciseFrom(buyer.address, longTokenId, amount),
          ).to.be.revertedWith('not ITM');
        });
      });
    });

    describe('#processExpired', function () {
      describe('call option', () => {
        it('processes expired option OTM', async () => {
          const isCall = true;
          const maturity = await getMaturity(20);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          const freeLiquidityTokenId = getFreeLiqTokenId(isCall);

          await p.depositLiquidity(lp1, amount, isCall);

          await underlying.mint(buyer.address, parseUnderlying('100'));
          await underlying
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          await ethers.provider.send('evm_setNextBlockTimestamp', [
            maturity.add(100).toNumber(),
          ]);

          const contractSizeProcessed = amount.div(ethers.constants.Two);

          const oldLongTokenSupply = await instance.callStatic.totalSupply(
            longTokenId,
          );
          const oldShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
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
            freeLiquidityTokenId,
          );

          await instance
            .connect(owner)
            .processExpired(longTokenId, contractSizeProcessed);

          const newLongTokenSupply = await instance.callStatic.totalSupply(
            longTokenId,
          );
          const newShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
          );
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
            freeLiquidityTokenId,
          );

          expect(newLongTokenSupply).to.equal(
            oldLongTokenSupply.sub(contractSizeProcessed),
          );
          expect(newShortTokenSupply).to.equal(
            oldShortTokenSupply.sub(contractSizeProcessed),
          );
          expect(newBuyerLongTokenBalance).to.equal(
            oldBuyerLongTokenBalance.sub(contractSizeProcessed),
          );
          expect(newLPShortTokenBalance).to.equal(
            oldLPShortTokenBalance.sub(contractSizeProcessed),
          );
          expect(newLPFreeLiquidityBalance).to.equal(
            oldLPFreeLiquidityBalance.add(contractSizeProcessed),
          );
        });

        it('processes expired option ITM', async () => {
          const isCall = true;
          const maturity = await getMaturity(20);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          const freeLiquidityTokenId = getFreeLiqTokenId(isCall);

          await p.depositLiquidity(lp1, amount, isCall);

          await underlying.mint(buyer.address, parseUnderlying('100'));
          await underlying
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          await ethers.provider.send('evm_setNextBlockTimestamp', [
            maturity.add(100).toNumber(),
          ]);

          const price = strike * 1.4;
          await p.setUnderlyingPrice(
            ethers.utils.parseUnits(price.toString(), 8),
          );

          const contractSizeProcessed = amount.div(ethers.constants.Two);

          const oldLongTokenSupply = await instance.callStatic.totalSupply(
            longTokenId,
          );
          const oldShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
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
            freeLiquidityTokenId,
          );

          await instance
            .connect(owner)
            .processExpired(longTokenId, contractSizeProcessed);

          const newLongTokenSupply = await instance.callStatic.totalSupply(
            longTokenId,
          );
          const newShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
          );
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
            freeLiquidityTokenId,
          );

          const exerciseValue = getExerciseValue(price, strike, 0.5, isCall);

          expect(newLongTokenSupply).to.equal(
            oldLongTokenSupply.sub(contractSizeProcessed),
          );
          expect(newShortTokenSupply).to.equal(
            oldShortTokenSupply.sub(contractSizeProcessed),
          );
          expect(newBuyerLongTokenBalance).to.equal(
            oldBuyerLongTokenBalance.sub(contractSizeProcessed),
          );
          expect(newLPShortTokenBalance).to.equal(
            oldLPShortTokenBalance.sub(contractSizeProcessed),
          );
          expect(newLPFreeLiquidityBalance).to.equal(
            oldLPFreeLiquidityBalance
              .add(contractSizeProcessed)
              .sub(parseUnderlying(exerciseValue.toString())),
          );
        });
      });

      describe('put option', () => {
        it('processes expired option OTM', async () => {
          const isCall = false;
          const maturity = await getMaturity(20);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          const freeLiquidityTokenId = getFreeLiqTokenId(isCall);

          await p.depositLiquidity(
            lp1,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );

          await base.mint(buyer.address, parseBase('100000'));
          await base
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          await ethers.provider.send('evm_setNextBlockTimestamp', [
            maturity.add(100).toNumber(),
          ]);

          const contractSizeProcessed = amount.div(ethers.constants.Two);
          const tokenAmount = parseBase(
            formatUnderlying(contractSizeProcessed),
          ).mul(fixedToNumber(strike64x64));

          const oldLongTokenSupply = await instance.callStatic.totalSupply(
            longTokenId,
          );
          const oldShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
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
            freeLiquidityTokenId,
          );

          await instance
            .connect(owner)
            .processExpired(longTokenId, contractSizeProcessed);

          const newLongTokenSupply = await instance.callStatic.totalSupply(
            longTokenId,
          );
          const newShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
          );
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
            freeLiquidityTokenId,
          );

          expect(newLongTokenSupply).to.equal(
            oldLongTokenSupply.sub(contractSizeProcessed),
          );
          expect(newShortTokenSupply).to.equal(
            oldShortTokenSupply.sub(contractSizeProcessed),
          );
          expect(newBuyerLongTokenBalance).to.equal(
            oldBuyerLongTokenBalance.sub(contractSizeProcessed),
          );
          expect(newLPShortTokenBalance).to.equal(
            oldLPShortTokenBalance.sub(contractSizeProcessed),
          );
          expect(newLPFreeLiquidityBalance).to.equal(
            oldLPFreeLiquidityBalance.add(tokenAmount),
          );
        });

        it('processes expired option ITM', async () => {
          const isCall = false;
          const maturity = await getMaturity(20);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          const freeLiquidityTokenId = getFreeLiqTokenId(isCall);

          await p.depositLiquidity(
            lp1,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );

          await base.mint(buyer.address, parseBase('100000'));
          await base
            .connect(buyer)
            .approve(instance.address, ethers.constants.MaxUint256);

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          await ethers.provider.send('evm_setNextBlockTimestamp', [
            maturity.add(100).toNumber(),
          ]);

          const price = strike * 0.7;
          await p.setUnderlyingPrice(
            ethers.utils.parseUnits(price.toString(), 8),
          );

          const contractSizeProcessed = amount.div(ethers.constants.Two);
          const tokenAmount = parseBase(
            formatUnderlying(contractSizeProcessed),
          ).mul(fixedToNumber(strike64x64));

          const oldLongTokenSupply = await instance.callStatic.totalSupply(
            longTokenId,
          );
          const oldShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
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
            freeLiquidityTokenId,
          );

          await instance
            .connect(owner)
            .processExpired(longTokenId, contractSizeProcessed);

          const newLongTokenSupply = await instance.callStatic.totalSupply(
            longTokenId,
          );
          const newShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
          );
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
            freeLiquidityTokenId,
          );

          const exerciseValue = getExerciseValue(price, strike, 0.5, isCall);

          expect(newLongTokenSupply).to.equal(
            oldLongTokenSupply.sub(contractSizeProcessed),
          );
          expect(newShortTokenSupply).to.equal(
            oldShortTokenSupply.sub(contractSizeProcessed),
          );
          expect(newBuyerLongTokenBalance).to.equal(
            oldBuyerLongTokenBalance.sub(contractSizeProcessed),
          );
          expect(newLPShortTokenBalance).to.equal(
            oldLPShortTokenBalance.sub(contractSizeProcessed),
          );
          expect(newLPFreeLiquidityBalance).to.equal(
            oldLPFreeLiquidityBalance
              .add(tokenAmount)
              .sub(parseBase(exerciseValue.toString())),
          );
        });
      });

      describe('reverts if', () => {
        it('option is not expired', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));
          const amount = parseUnderlying('1');

          await p.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            instance.connect(buyer).processExpired(longTokenId, amount),
          ).to.be.revertedWith('not expired');
        });
      });
    });
  });
}
