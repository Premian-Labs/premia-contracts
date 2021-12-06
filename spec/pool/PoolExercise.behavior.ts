import { ethers } from 'hardhat';
import { expect } from 'chai';
import {
  IPool,
  FeeDiscount,
  ERC20Mock,
  ERC20Mock__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { BigNumber, ContractTransaction } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
  TokenType,
} from '@premia/utils';

import { bnToNumber } from '../../test/utils/math';

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
} from '../../test/pool/PoolUtil';

interface PoolExerciseBehaviorArgs {
  deploy: () => Promise<IPool>;
  getFeeDiscount: () => Promise<FeeDiscount>;
  getXPremia: () => Promise<ERC20Mock>;
  getPoolUtil: () => Promise<PoolUtil>;
}

import {
  createUniswap,
  createUniswapPair,
  depositUniswapLiquidity,
  IUniswap,
} from '../../test/utils/uniswap';

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
          it('should revert if token is a SHORT token', async () => {
            const maturity = await p.getMaturity(10);
            const strike64x64 = fixedFromFloat(p.getStrike(isCall, 2000));

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
              instance
                .connect(buyer)
                .exerciseFrom(
                  buyer.address,
                  shortTokenId,
                  parseUnderlying('1'),
                ),
            ).to.be.revertedWith('invalid type');
          });

          it('should revert if option is not ITM', async () => {
            const maturity = await p.getMaturity(10);
            const strike64x64 = fixedFromFloat(p.getStrike(isCall, 2000));

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
              instance
                .connect(buyer)
                .exerciseFrom(buyer.address, longTokenId, parseUnderlying('1')),
            ).to.be.revertedWith('not ITM');
          });

          it('should successfully apply staking fee discount on exercise', async () => {
            const maturity = await p.getMaturity(10);
            const strike = p.getStrike(isCall, 2000);
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

            const feeDiscount = await getFeeDiscount();
            const xPremia = await getXPremia();

            // Stake xPremia for fee discount
            await xPremia.mint(buyer.address, ethers.utils.parseEther('5000'));
            await xPremia.mint(lp1.address, ethers.utils.parseEther('50000'));
            await xPremia
              .connect(buyer)
              .approve(feeDiscount.address, ethers.constants.MaxUint256);
            await xPremia
              .connect(lp1)
              .approve(feeDiscount.address, ethers.constants.MaxUint256);
            await feeDiscount
              .connect(buyer)
              .stake(ethers.utils.parseEther('5000'), ONE_MONTH);
            await feeDiscount
              .connect(lp1)
              .stake(ethers.utils.parseEther('50000'), ONE_MONTH);

            //

            expect(await feeDiscount.getDiscount(buyer.address)).to.eq(2500);
            expect(await feeDiscount.getDiscount(lp1.address)).to.eq(5000);

            const longTokenId = formatTokenId({
              tokenType: p.getLong(isCall),
              maturity,
              strike64x64,
            });

            const price = isCall ? strike * 1.4 : strike * 0.7;
            await p.setUnderlyingPrice(
              ethers.utils.parseUnits(price.toString(), 8),
            );

            const curBalance = await p
              .getToken(isCall)
              .balanceOf(buyer.address);

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
            ).sub(curBalance);

            expect(Number(formatOption(premium, isCall))).to.almost(
              exerciseValue * (1 - FEE * 0.75),
            );
            expect(await instance.balanceOf(buyer.address, longTokenId)).to.eq(
              0,
            );

            const freeLiqAfter = await instance.balanceOf(
              lp1.address,
              p.getFreeLiqTokenId(isCall),
            );

            // Free liq = initial amount + premia paid
            expect(
              Number(formatOption(initialFreeLiqAmount, isCall)) -
                exerciseValue +
                fixedToNumber(quote.baseCost64x64),
            ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
          });

          it('should successfully exercise', async () => {
            const maturity = await p.getMaturity(10);
            const strike = p.getStrike(isCall, 2000);
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
            await p.setUnderlyingPrice(
              ethers.utils.parseUnits(price.toString(), 8),
            );

            const curBalance = await p
              .getToken(isCall)
              .balanceOf(buyer.address);

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
            ).sub(curBalance);

            expect(Number(formatOption(premium, isCall))).to.almost(
              exerciseValue * (1 - FEE),
            );
            expect(await instance.balanceOf(buyer.address, longTokenId)).to.eq(
              0,
            );

            const freeLiqAfter = await instance.balanceOf(
              lp1.address,
              p.getFreeLiqTokenId(isCall),
            );

            // Free liq = initial amount + premia paid
            expect(
              Number(formatOption(initialFreeLiqAmount, isCall)) -
                exerciseValue +
                fixedToNumber(quote.baseCost64x64),
            ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
          });

          it('should revert when exercising on behalf of user not approved', async () => {
            const maturity = await p.getMaturity(10);
            const strike = p.getStrike(isCall, 2000);
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
              instance
                .connect(thirdParty)
                .exerciseFrom(buyer.address, longTokenId, amount),
            ).to.be.revertedWith('not approved');
          });

          it('should succeed when exercising on behalf of user approved', async () => {
            const maturity = await p.getMaturity(10);
            const strike = p.getStrike(isCall, 2000);
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
            await p.setUnderlyingPrice(
              ethers.utils.parseUnits(price.toString(), 8),
            );

            const curBalance = await p
              .getToken(isCall)
              .balanceOf(buyer.address);

            await instance
              .connect(buyer)
              .setApprovalForAll(thirdParty.address, true);

            await instance
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

            expect(await instance.balanceOf(buyer.address, longTokenId)).to.eq(
              0,
            );

            const freeLiqAfter = await instance.balanceOf(
              lp1.address,
              p.getFreeLiqTokenId(isCall),
            );

            // Free liq = initial amount + premia paid
            expect(
              Number(formatOption(initialFreeLiqAmount, isCall)) -
                exerciseValue +
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
            const strike64x64 = fixedFromFloat(p.getStrike(isCall, 2000));

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
              instance
                .connect(buyer)
                .processExpired(longTokenId, parseUnderlying('1')),
            ).to.be.revertedWith('not expired');
          });

          it('should successfully process expired option OTM', async () => {
            const maturity = await p.getMaturity(20);
            const strike = p.getStrike(isCall, 2000);
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

            await ethers.provider.send('evm_setNextBlockTimestamp', [
              maturity.add(100).toNumber(),
            ]);

            const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

            const price = isCall ? strike * 0.7 : strike * 1.4;
            await p.setUnderlyingPrice(
              ethers.utils.parseUnits(price.toString(), 8),
            );

            // Free liq = premia paid after purchase
            expect(
              Number(
                formatOption(
                  await instance.balanceOf(
                    lp1.address,
                    p.getFreeLiqTokenId(isCall),
                  ),
                  isCall,
                ),
              ),
            ).to.almost(fixedToNumber(quote.baseCost64x64));

            // Process expired
            await instance
              .connect(buyer)
              .processExpired(tokenId.long, parseUnderlying('1'));

            expect(await instance.balanceOf(buyer.address, tokenId.long)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp1.address, tokenId.short)).to.eq(
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

            const freeLiqAfter = await instance.balanceOf(
              lp1.address,
              p.getFreeLiqTokenId(isCall),
            );

            // Free liq = initial amount + premia paid
            expect(
              Number(formatOption(initialFreeLiqAmount, isCall)) +
                fixedToNumber(quote.baseCost64x64),
            ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
          });

          it('should successfully process expired option ITM', async () => {
            const maturity = await p.getMaturity(20);
            const strike = p.getStrike(isCall, 2000);
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

            await ethers.provider.send('evm_setNextBlockTimestamp', [
              maturity.add(100).toNumber(),
            ]);

            const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

            const price = isCall ? strike * 1.4 : strike * 0.7;
            await p.setUnderlyingPrice(
              ethers.utils.parseUnits(price.toString(), 8),
            );

            // Free liq = premia paid after purchase
            expect(
              Number(
                formatOption(
                  await instance.balanceOf(
                    lp1.address,
                    p.getFreeLiqTokenId(isCall),
                  ),
                  isCall,
                ),
              ),
            ).to.almost(fixedToNumber(quote.baseCost64x64));

            // Process expired
            await instance
              .connect(buyer)
              .processExpired(tokenId.long, parseUnderlying('1'));

            expect(await instance.balanceOf(buyer.address, tokenId.long)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp1.address, tokenId.short)).to.eq(
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
                exerciseValue * (1 - FEE),
            );

            const freeLiqAfter = await instance.balanceOf(
              lp1.address,
              p.getFreeLiqTokenId(isCall),
            );

            // Free liq = initial amount + premia paid - exerciseValue
            expect(
              Number(formatOption(initialFreeLiqAmount, isCall)) -
                exerciseValue +
                fixedToNumber(quote.baseCost64x64),
            ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
          });
        });
      }
    });
  });
}
