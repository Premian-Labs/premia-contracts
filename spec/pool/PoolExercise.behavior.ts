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
  getFeeDiscount: () => Promise<FeeDiscount>;
  getXPremia: () => Promise<ERC20Mock>;
  getPoolUtil: () => Promise<PoolUtil>;
}

const ONE_MONTH = 30 * 24 * 3600;

export function describeBehaviorOfPoolExercise({
  deploy,
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
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('should successfully process expired option OTM', async () => {
            const maturity = await getMaturity(20);
            const strike = getStrike(isCall, 2000);
            const strike64x64 = fixedFromFloat(strike);
            const amount = parseUnderlying('1');

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

            await ethers.provider.send('evm_setNextBlockTimestamp', [
              maturity.add(100).toNumber(),
            ]);

            const freeLiquidityTokenId = getFreeLiqTokenId(isCall);
            const { long: longTokenId, short: shortTokenId } =
              getOptionTokenIds(maturity, strike64x64, isCall);

            const price = isCall ? strike * 0.7 : strike * 1.4;
            await p.setUnderlyingPrice(
              ethers.utils.parseUnits(price.toString(), 8),
            );

            // Free liq = premia paid after purchase
            expect(
              Number(
                formatOption(
                  await instance.balanceOf(lp1.address, freeLiquidityTokenId),
                  isCall,
                ),
              ),
            ).to.almost(fixedToNumber(quote.baseCost64x64));

            const oldFreeLiquidity = isCall
              ? amount
              : parseBase(formatUnderlying(amount)).mul(
                  fixedToNumber(strike64x64),
                );

            // Process expired
            await instance
              .connect(buyer)
              .processExpired(longTokenId, parseUnderlying('1'));

            expect(await instance.balanceOf(buyer.address, longTokenId)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp1.address, shortTokenId)).to.eq(
              0,
            );

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

            const newFreeLiquidity = await instance.balanceOf(
              lp1.address,
              freeLiquidityTokenId,
            );

            // Free liq = initial amount + premia paid
            expect(Number(formatOption(newFreeLiquidity, isCall))).to.almost(
              Number(formatOption(oldFreeLiquidity, isCall)) +
                fixedToNumber(quote.baseCost64x64),
            );
          });

          it('should successfully process expired option ITM', async () => {
            const maturity = await getMaturity(20);
            const strike = getStrike(isCall, 2000);
            const strike64x64 = fixedFromFloat(strike);

            const amount = parseUnderlying('1');
            const oldFreeLiquidity = isCall
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

            await ethers.provider.send('evm_setNextBlockTimestamp', [
              maturity.add(100).toNumber(),
            ]);

            const freeLiquidityTokenId = getFreeLiqTokenId(isCall);
            const { long: longTokenId, short: shortTokenId } =
              getOptionTokenIds(maturity, strike64x64, isCall);

            const price = isCall ? strike * 1.4 : strike * 0.7;
            await p.setUnderlyingPrice(
              ethers.utils.parseUnits(price.toString(), 8),
            );

            // Free liq = premia paid after purchase
            expect(
              Number(
                formatOption(
                  await instance.balanceOf(lp1.address, freeLiquidityTokenId),
                  isCall,
                ),
              ),
            ).to.almost(fixedToNumber(quote.baseCost64x64));

            // Process expired
            await instance
              .connect(buyer)
              .processExpired(longTokenId, parseUnderlying('1'));

            expect(await instance.balanceOf(buyer.address, longTokenId)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp1.address, shortTokenId)).to.eq(
              0,
            );

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
                exerciseValue,
            );

            const newFreeLiquidity = await instance.balanceOf(
              lp1.address,
              freeLiquidityTokenId,
            );

            // Free liq = initial amount + premia paid - exerciseValue
            expect(Number(formatOption(newFreeLiquidity, isCall))).to.almost(
              Number(formatOption(oldFreeLiquidity, isCall)) +
                fixedToNumber(quote.baseCost64x64) -
                exerciseValue,
            );
          });
        });
      }

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
