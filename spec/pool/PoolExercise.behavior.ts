import { ethers } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, FeeDiscount, IPool } from '../../typechain';
import { BigNumberish } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { fixedFromFloat, fixedToNumber, formatTokenId } from '@premia/utils';

import {
  formatUnderlying,
  getExerciseValue,
  getFreeLiqTokenId,
  getLong,
  getMaturity,
  getShort,
  getStrike,
  ONE_YEAR,
  parseBase,
  parseUnderlying,
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
  apyFeeRate: BigNumberish;
}

export function describeBehaviorOfPoolExercise({
  deploy,
  getUnderlying,
  getBase,
  getFeeDiscount,
  getXPremia,
  getPoolUtil,
  apyFeeRate,
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
      describe('call option', () => {
        it('exercises on behalf of sender without approval', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          await p.depositLiquidity(lp1, amount, isCall);

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          await ethers.provider.send('evm_increaseTime', [5 * 24 * 3600]);

          const price = strike * 1.4;
          await p.setUnderlyingPrice(price);

          await expect(
            instance
              .connect(buyer)
              .exerciseFrom(buyer.address, longTokenId, amount),
          ).not.to.be.reverted;
        });

        it('burns long tokens from holder and corresponding short tokens from underwriter', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
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

          await p.depositLiquidity(lp1, amount, isCall);

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          await ethers.provider.send('evm_increaseTime', [5 * 24 * 3600]);

          await instance
            .connect(buyer)
            .setApprovalForAll(thirdParty.address, true);

          const price = strike * 1.4;
          await p.setUnderlyingPrice(price);

          const contractSizeExercised = amount.div(ethers.constants.Two);

          const oldLongTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            longTokenId,
          );
          const oldShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
          );

          await instance
            .connect(thirdParty)
            .exerciseFrom(buyer.address, longTokenId, contractSizeExercised);

          const newLongTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            longTokenId,
          );
          const newShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
          );

          expect(newLongTokenBalance).to.equal(
            oldLongTokenBalance.sub(contractSizeExercised),
          );
          expect(newShortTokenSupply).to.equal(
            oldShortTokenSupply.sub(contractSizeExercised),
          );
        });

        it('transfers exercise value to holder', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
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

          await p.depositLiquidity(lp1, amount, isCall);

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          await ethers.provider.send('evm_increaseTime', [5 * 24 * 3600]);

          await instance
            .connect(buyer)
            .setApprovalForAll(thirdParty.address, true);

          const price = strike * 1.4;
          await p.setUnderlyingPrice(price);

          const contractSizeExercised = amount.div(ethers.constants.Two);

          const oldBalance = await underlying.callStatic.balanceOf(
            buyer.address,
          );

          await instance
            .connect(thirdParty)
            .exerciseFrom(buyer.address, longTokenId, contractSizeExercised);

          const newBalance = await underlying.callStatic.balanceOf(
            buyer.address,
          );

          const exerciseValue = contractSizeExercised
            .mul(parseUnderlying(((price - strike) / price).toString()))
            .div(parseUnderlying('1'));

          expect(newBalance).to.equal(oldBalance.add(exerciseValue));
        });

        it('processes divestment');

        it('deducts exercise value from TVL', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
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

          await p.depositLiquidity(lp1, amount, isCall);

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          await ethers.provider.send('evm_increaseTime', [5 * 24 * 3600]);

          await instance
            .connect(buyer)
            .setApprovalForAll(thirdParty.address, true);

          const price = strike * 1.4;
          await p.setUnderlyingPrice(price);

          const contractSizeExercised = amount.div(ethers.constants.Two);

          const { underlyingTVL: oldUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(thirdParty)
            .exerciseFrom(buyer.address, longTokenId, contractSizeExercised);

          const { blockNumber } = await tx.wait();
          const { timestamp } = await ethers.provider.getBlock(blockNumber);

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const exerciseValue = contractSizeExercised
            .mul(parseUnderlying(((price - strike) / price).toString()))
            .div(parseUnderlying('1'));

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(timestamp))
            .mul(contractSizeExercised)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          expect(newUserTVL).to.equal(
            oldUserTVL.sub(exerciseValue).add(apyFeeRemaining),
          );

          expect(newTotalTVL).to.equal(
            oldTotalTVL.sub(exerciseValue).add(apyFeeRemaining),
          );
        });
      });

      describe('put option', () => {
        it('exercises on behalf of sender without approval', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          await p.depositLiquidity(
            lp1,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
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

          await ethers.provider.send('evm_increaseTime', [5 * 24 * 3600]);

          const price = strike * 0.7;
          await p.setUnderlyingPrice(price);

          await expect(
            instance
              .connect(buyer)
              .exerciseFrom(buyer.address, longTokenId, amount),
          ).not.to.be.reverted;
        });

        it('burns long tokens from holder and corresponding short tokens from underwriter', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
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

          await p.depositLiquidity(
            lp1,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
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

          await ethers.provider.send('evm_increaseTime', [5 * 24 * 3600]);

          await instance
            .connect(buyer)
            .setApprovalForAll(thirdParty.address, true);

          const price = strike * 0.7;
          await p.setUnderlyingPrice(price);

          const contractSizeExercised = amount.div(ethers.constants.Two);

          const oldLongTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            longTokenId,
          );
          const oldShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
          );

          await instance
            .connect(thirdParty)
            .exerciseFrom(buyer.address, longTokenId, contractSizeExercised);

          const newLongTokenBalance = await instance.callStatic.balanceOf(
            buyer.address,
            longTokenId,
          );
          const newShortTokenSupply = await instance.callStatic.totalSupply(
            shortTokenId,
          );

          expect(newLongTokenBalance).to.equal(
            oldLongTokenBalance.sub(contractSizeExercised),
          );
          expect(newShortTokenSupply).to.equal(
            oldShortTokenSupply.sub(contractSizeExercised),
          );
        });

        it('transfers exercise value to holder', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
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

          await p.depositLiquidity(
            lp1,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
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

          await ethers.provider.send('evm_increaseTime', [5 * 24 * 3600]);

          await instance
            .connect(buyer)
            .setApprovalForAll(thirdParty.address, true);

          const price = strike * 0.7;
          await p.setUnderlyingPrice(price);

          const contractSizeExercised = amount.div(ethers.constants.Two);

          const oldBalance = await base.callStatic.balanceOf(buyer.address);

          await instance
            .connect(thirdParty)
            .exerciseFrom(buyer.address, longTokenId, contractSizeExercised);

          const newBalance = await base.callStatic.balanceOf(buyer.address);

          const exerciseValue = parseBase(
            formatUnderlying(
              contractSizeExercised
                .mul(parseUnderlying((strike - price).toString()))
                .div(parseUnderlying('1')),
            ),
          );

          expect(newBalance).to.equal(oldBalance.add(exerciseValue));
        });

        it('processes divestment');

        it('deducts exercise value from TVL', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
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

          await p.depositLiquidity(
            lp1,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
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

          await ethers.provider.send('evm_increaseTime', [5 * 24 * 3600]);

          await instance
            .connect(buyer)
            .setApprovalForAll(thirdParty.address, true);

          const price = strike * 0.7;
          await p.setUnderlyingPrice(price);

          const contractSizeExercised = amount.div(ethers.constants.Two);
          const tokenAmount = parseBase(
            formatUnderlying(contractSizeExercised),
          ).mul(fixedToNumber(strike64x64));

          const { baseTVL: oldUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(thirdParty)
            .exerciseFrom(buyer.address, longTokenId, contractSizeExercised);

          const { blockNumber } = await tx.wait();
          const { timestamp } = await ethers.provider.getBlock(blockNumber);

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const exerciseValue = parseBase(
            formatUnderlying(
              contractSizeExercised
                .mul(parseUnderlying((strike - price).toString()))
                .div(parseUnderlying('1')),
            ),
          );

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(timestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          expect(newUserTVL).to.equal(
            oldUserTVL.sub(exerciseValue).add(apyFeeRemaining),
          );

          expect(newTotalTVL).to.equal(
            oldTotalTVL.sub(exerciseValue).add(apyFeeRemaining),
          );
        });
      });

      describe('reverts if', () => {
        it('token is a short token', async () => {
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
          await p.setUnderlyingPrice(price);

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

        it('processes divestment');

        it('updates TVL');
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
          await p.setUnderlyingPrice(price);

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

        it('processes divestment');

        it('updates TVL');
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
