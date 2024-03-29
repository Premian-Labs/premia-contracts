import { ethers } from 'hardhat';
import { expect } from 'chai';
import { ERC20Mock, IPool } from '../../typechain';
import { BigNumberish } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { fixedFromFloat, fixedToNumber, formatTokenId } from '@premia/utils';

import { IUniswap, uniswapABIs } from '../../test/utils/uniswap';

import {
  formatUnderlying,
  getFreeLiqTokenId,
  getLong,
  getMaturity,
  getReservedLiqTokenId,
  getShort,
  getStrike,
  ONE_YEAR,
  parseBase,
  parseOption,
  parseUnderlying,
  PoolUtil,
} from '../../test/pool/PoolUtil';

interface PoolIOBehaviorArgs {
  getBase: () => Promise<ERC20Mock>;
  getUnderlying: () => Promise<ERC20Mock>;
  getPoolUtil: () => Promise<PoolUtil>;
  apyFeeRate: BigNumberish;
  getUniswap: () => Promise<IUniswap>;
}

export function describeBehaviorOfPoolIO(
  deploy: () => Promise<IPool>,
  {
    getBase,
    getUnderlying,
    getPoolUtil,
    apyFeeRate,
    getUniswap,
  }: PoolIOBehaviorArgs,
) {
  describe('::PoolIO', () => {
    let owner: SignerWithAddress;
    let buyer: SignerWithAddress;
    let lp1: SignerWithAddress;
    let lp2: SignerWithAddress;
    let instance: IPool;
    let base: ERC20Mock;
    let underlying: ERC20Mock;
    let p: PoolUtil;
    let uniswap: IUniswap;
    let exchangeHelperAddress: string;

    before(async () => {
      [owner, buyer, lp1, lp2] = await ethers.getSigners();
    });

    beforeEach(async () => {
      instance = await deploy();
      // TODO: don't
      p = await getPoolUtil();
      uniswap = await getUniswap();
      base = await getBase();
      underlying = await getUnderlying();
      exchangeHelperAddress = await instance.callStatic.getExchangeHelper();
    });

    // TODO: test #annihilate, #reassign, and #reassignBatch with divest = false

    describe('#setDivestmentTimestamp', () => {
      it('sets divestment timestamp and unsets if zero timestamp is passed', async () => {
        const isCall = false;

        let { timestamp } = await ethers.provider.getBlock('latest');

        await instance.connect(lp1).setDivestmentTimestamp(timestamp, isCall);

        expect(
          (await instance.callStatic.getDivestmentTimestamps(lp1.address))[
            +!isCall
          ],
        ).to.equal(timestamp);

        await instance
          .connect(lp1)
          .setDivestmentTimestamp(ethers.constants.Zero, isCall);

        expect(
          (await instance.callStatic.getDivestmentTimestamps(lp1.address))[
            +!isCall
          ],
        ).to.equal(ethers.constants.Zero);
      });

      describe('reverts if', () => {
        it('timestamp is less than one day after last deposit and greater than zero', async () => {
          const isCall = false;

          await instance.connect(lp1).deposit(ethers.constants.Zero, isCall);

          let { timestamp } = await ethers.provider.getBlock('latest');

          await expect(
            instance
              .connect(lp1)
              .setDivestmentTimestamp(timestamp + 86400 - 1, isCall),
          ).to.be.revertedWith('liq lock 1d');

          await expect(
            instance.setDivestmentTimestamp(timestamp + 86400, isCall),
          ).not.to.be.reverted;

          await expect(
            instance
              .connect(lp1)
              .setDivestmentTimestamp(ethers.constants.Zero, isCall),
          ).not.to.be.reverted;
        });
      });
    });

    describe('#deposit', function () {
      it('should reset divestment timestamp', async () => {
        const { timestamp } = await ethers.provider.getBlock('latest');

        await instance
          .connect(lp1)
          .setDivestmentTimestamp(timestamp + 25 * 3600, true);

        await instance
          .connect(lp1)
          .setDivestmentTimestamp(timestamp + 25 * 3600, false);

        await p.depositLiquidity(lp1, parseOption('1', true), true);

        let timestamps = await instance.getDivestmentTimestamps(lp1.address);
        expect(timestamps.callDivestmentTimestamp).to.eq(0);
        expect(timestamps.putDivestmentTimestamp).to.eq(timestamp + 25 * 3600);

        await p.depositLiquidity(lp1, parseOption('1', false), false);

        timestamps = await instance.getDivestmentTimestamps(lp1.address);
        expect(timestamps.callDivestmentTimestamp).to.eq(0);
        expect(timestamps.putDivestmentTimestamp).to.eq(0);
      });

      describe('call', () => {
        it('should grant sender share tokens with ERC20 deposit', async () => {
          await expect(() =>
            instance.deposit('100', true),
          ).to.changeTokenBalance(p.underlying, owner, -100);
          expect(
            await instance.balanceOf(owner.address, getFreeLiqTokenId(true)),
          ).to.eq(100);
        });

        it('should grant sender share tokens with WETH deposit', async () => {
          // Use WETH tokens
          await p.weth.deposit({ value: 100 });
          await p.weth.approve(p.poolWeth.address, ethers.constants.MaxUint256);
          await expect(() =>
            p.poolWeth.deposit('50', true),
          ).to.changeTokenBalance(p.weth, owner, -50);

          // Use ETH
          await expect(() =>
            p.poolWeth.deposit('200', true, { value: 200 }),
          ).to.changeEtherBalance(owner, -200);

          // Use both ETH and WETH tokens
          await expect(() =>
            p.poolWeth.deposit('100', true, { value: 50 }),
          ).to.changeEtherBalance(owner, -50);

          expect(await p.weth.balanceOf(owner.address)).to.eq(0);
          expect(
            await p.poolWeth.balanceOf(owner.address, getFreeLiqTokenId(true)),
          ).to.eq(350);
        });

        it('should revert if user send ETH with a token deposit', async () => {
          await expect(
            instance.deposit('100', true, { value: 1 }),
          ).to.be.revertedWith('not WETH deposit');
        });

        it('should refund excess if user send too much ETH with a WETH deposit', async () => {
          await expect(() =>
            p.poolWeth.connect(owner).deposit('200', true, { value: 201 }),
          ).to.changeEtherBalance(owner, -200);
        });

        it('increases user TVL and total TVL', async () => {
          const isCall = true;
          const amount = parseOption('10', isCall);

          const amountDeposited = amount.div(ethers.constants.Two);

          const { underlyingTVL: oldUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          await instance.connect(lp1).deposit(amountDeposited, isCall);

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.equal(oldUserTVL.add(amountDeposited));
          expect(newTotalTVL).to.equal(oldTotalTVL.add(amountDeposited));
        });
      });

      describe('put', () => {
        it('should grant sender share tokens with ERC20 deposit', async () => {
          await expect(() =>
            instance.deposit('100', false),
          ).to.changeTokenBalance(p.base, owner, -100);
          expect(
            await instance.balanceOf(owner.address, getFreeLiqTokenId(false)),
          ).to.eq(100);
        });

        it('increases user TVL and total TVL', async () => {
          const isCall = false;
          const amount = parseOption('10', isCall);

          const amountDeposited = amount.div(ethers.constants.Two);

          const { baseTVL: oldUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          await instance.connect(lp1).deposit(amountDeposited, isCall);

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.equal(oldUserTVL.add(amountDeposited));
          expect(newTotalTVL).to.equal(oldTotalTVL.add(amountDeposited));
        });
      });
    });

    describe('#swapAndDeposit', function () {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('executes deposit using non-pool ERC20 token', async () => {
            const amountBefore = await instance.balanceOf(
              buyer.address,
              getFreeLiqTokenId(isCall),
            );

            const amount = isCall
              ? parseOption('0.1', isCall)
              : parseOption('1000', isCall);

            const swapTokenIn = isCall ? p.base.address : p.underlying.address;
            const swapTokenOut = isCall ? p.underlying.address : p.base.address;

            const uniswapPath = [
              swapTokenIn,
              uniswap.weth.address,
              swapTokenOut,
            ];

            const maxTokenIn = isCall
              ? ethers.utils.parseEther('10000')
              : ethers.utils.parseEther('10');

            const { timestamp } = await ethers.provider.getBlock('latest');

            const iface = new ethers.utils.Interface(uniswapABIs);
            const data = iface.encodeFunctionData('swapTokensForExactTokens', [
              amount,
              maxTokenIn,
              uniswapPath,
              exchangeHelperAddress,
              timestamp + 86400,
            ]);

            await instance.connect(buyer).swapAndDeposit(
              {
                tokenIn: swapTokenIn,
                amountInMax: maxTokenIn,
                amountOutMin: amount,
                callee: uniswap.router.address,
                allowanceTarget: uniswap.router.address,
                data,
                refundAddress: buyer.address,
              },
              isCall,
            );

            const amountAfter = await instance.balanceOf(
              buyer.address,
              getFreeLiqTokenId(isCall),
            );

            expect(amountAfter.sub(amountBefore)).to.eq(amount);
          });

          it('executes deposit using ETH', async () => {
            const amountBefore = await instance.balanceOf(
              buyer.address,
              getFreeLiqTokenId(isCall),
            );

            const amount = isCall
              ? parseOption('0.1', isCall)
              : parseOption('1000', isCall);

            const tokenIn = uniswap.weth.address;
            const uniswapPath = isCall
              ? [uniswap.weth.address, p.underlying.address]
              : [uniswap.weth.address, p.base.address];

            const { timestamp } = await ethers.provider.getBlock('latest');

            const maxEthToPay = ethers.utils.parseEther('2');

            const iface = new ethers.utils.Interface(uniswapABIs);

            // eth will be wrap into weth, so we call uniswap to trade weth to pool token
            const data = iface.encodeFunctionData('swapTokensForExactTokens', [
              amount,
              maxEthToPay,
              uniswapPath,
              exchangeHelperAddress,
              timestamp + 86400,
            ]);

            await instance.connect(buyer).swapAndDeposit(
              {
                tokenIn,
                amountInMax: 0,
                amountOutMin: amount,
                callee: uniswap.router.address,
                allowanceTarget: uniswap.router.address,
                data,
                refundAddress: buyer.address,
              },
              isCall,
              {
                value: maxEthToPay,
              },
            );

            const amountAfter = await instance.balanceOf(
              buyer.address,
              getFreeLiqTokenId(isCall),
            );

            expect(amountAfter.sub(amountBefore)).to.eq(amount);
          });

          it('executes swapAndDeposit using ETH and weth', async () => {
            // only for put pool
            if (isCall) return;

            const amountBefore = await instance.balanceOf(
              buyer.address,
              getFreeLiqTokenId(isCall),
            );

            const amount = parseOption('1000', isCall);

            const tokenIn = uniswap.weth.address;
            const uniswapPath = [uniswap.weth.address, p.base.address];

            const { timestamp } = await ethers.provider.getBlock('latest');

            const totalAmountToPay = ethers.utils.parseEther('2');

            const inAmountInEth = totalAmountToPay.div(2);
            const inAmountInWeth = totalAmountToPay.sub(inAmountInEth);

            // mint some weth
            await uniswap.weth
              .connect(buyer)
              .deposit({ value: inAmountInWeth });
            await uniswap.weth
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);

            const [, expectedAmountOut] = await uniswap.router.getAmountsOut(
              totalAmountToPay,
              uniswapPath,
            );

            const iface = new ethers.utils.Interface(uniswapABIs);

            const data = iface.encodeFunctionData('swapExactTokensForTokens', [
              totalAmountToPay, // amountIn
              amount, // amountOut min
              uniswapPath,
              exchangeHelperAddress,
              timestamp + 86400,
            ]);

            await instance.connect(buyer).swapAndDeposit(
              {
                tokenIn,
                amountInMax: inAmountInWeth,
                amountOutMin: amount,
                callee: uniswap.router.address,
                allowanceTarget: uniswap.router.address,
                data,
                refundAddress: buyer.address,
              },
              isCall,
              {
                value: inAmountInEth,
              },
            );

            const wethBalanceAfter = await uniswap.weth.balanceOf(
              buyer.address,
            );

            const amountAfter = await instance.balanceOf(
              buyer.address,
              getFreeLiqTokenId(isCall),
            );

            expect(wethBalanceAfter).to.eq(0);
            expect(amountAfter.sub(amountBefore).eq(expectedAmountOut)).to.be
              .true;
          });
        });
      }
    });

    describe('#withdraw', function () {
      describe('call option', () => {
        it('processes withdrawal of reserved liquidity', async () => {
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

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const oldTokenBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );
          const oldReservedLiquidityBalance =
            await instance.callStatic.balanceOf(
              lp1.address,
              getReservedLiqTokenId(isCall),
            );
          const { underlyingTVL: oldUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const amountWithdrawn = oldReservedLiquidityBalance.div(
            ethers.constants.Two,
          );

          await instance.connect(lp1).withdraw(amountWithdrawn, isCall);

          const newTokenBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );
          const newReservedLiquidityBalance =
            await instance.callStatic.balanceOf(
              lp1.address,
              getReservedLiqTokenId(isCall),
            );
          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newTokenBalance).to.equal(
            oldTokenBalance.add(amountWithdrawn),
          );
          expect(newReservedLiquidityBalance).to.equal(
            oldReservedLiquidityBalance.sub(amountWithdrawn),
          );
          expect(newUserTVL).to.equal(oldUserTVL);
          expect(newTotalTVL).to.equal(oldTotalTVL);
        });
      });

      describe('put option', () => {
        it('processes withdrawal of reserved liquidity', async () => {
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

          await instance
            .connect(buyer)
            .purchase(
              maturity,
              strike64x64,
              amount,
              isCall,
              ethers.constants.MaxUint256,
            );

          const oldTokenBalance = await base.callStatic.balanceOf(lp1.address);
          const oldReservedLiquidityBalance =
            await instance.callStatic.balanceOf(
              lp1.address,
              getReservedLiqTokenId(isCall),
            );
          const { baseTVL: oldUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const amountWithdrawn = oldReservedLiquidityBalance.div(
            ethers.constants.Two,
          );

          await instance.connect(lp1).withdraw(amountWithdrawn, isCall);

          const newTokenBalance = await base.callStatic.balanceOf(lp1.address);
          const newReservedLiquidityBalance =
            await instance.callStatic.balanceOf(
              lp1.address,
              getReservedLiqTokenId(isCall),
            );
          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newTokenBalance).to.equal(
            oldTokenBalance.add(amountWithdrawn),
          );
          expect(newReservedLiquidityBalance).to.equal(
            oldReservedLiquidityBalance.sub(amountWithdrawn),
          );
          expect(newUserTVL).to.equal(oldUserTVL);
          expect(newTotalTVL).to.equal(oldTotalTVL);
        });
      });

      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('transfers liquidity to sender', async () => {
            const freeLiqTokenId = getFreeLiqTokenId(isCall);

            await p.depositLiquidity(lp1, 100, isCall);
            await ethers.provider.send('evm_increaseTime', [24 * 3600 + 60]);

            const oldFreeLiquidityBalance = await instance.callStatic.balanceOf(
              lp1.address,
              freeLiqTokenId,
            );
            const oldTokenBalance = await (isCall
              ? underlying
              : base
            ).callStatic.balanceOf(lp1.address);

            const amountWithdrawn = ethers.constants.Two;

            await instance.connect(lp1).withdraw(amountWithdrawn, isCall);

            const newFreeLiquidityBalance = await instance.callStatic.balanceOf(
              lp1.address,
              freeLiqTokenId,
            );
            const newTokenBalance = await (isCall
              ? underlying
              : base
            ).callStatic.balanceOf(lp1.address);

            expect(newFreeLiquidityBalance).to.equal(
              oldFreeLiquidityBalance.sub(amountWithdrawn),
            );
            expect(newTokenBalance).to.equal(
              oldTokenBalance.add(amountWithdrawn),
            );
          });

          it('decreases user TVL and total TVL', async () => {
            const amount = parseOption('10', isCall);

            await instance.connect(lp1).deposit(amount, isCall);

            await ethers.provider.send('evm_increaseTime', [24 * 3600 + 1]);

            const amountWithdrawn = amount.div(ethers.constants.Two);

            const tvlKey = isCall ? 'underlyingTVL' : 'baseTVL';

            const { [tvlKey]: oldUserTVL } =
              await instance.callStatic.getUserTVL(lp1.address);
            const { [tvlKey]: oldTotalTVL } =
              await instance.callStatic.getTotalTVL();

            await instance.connect(lp1).withdraw(amountWithdrawn, isCall);

            const { [tvlKey]: newUserTVL } =
              await instance.callStatic.getUserTVL(lp1.address);
            const { [tvlKey]: newTotalTVL } =
              await instance.callStatic.getTotalTVL();

            expect(newUserTVL).to.equal(oldUserTVL.sub(amountWithdrawn));
            expect(newTotalTVL).to.equal(oldTotalTVL.sub(amountWithdrawn));
          });
        });
      }

      describe('reverts if', () => {
        it('liquidity lock is in effect', async () => {
          const isCall = false;

          await p.depositLiquidity(owner, 100, isCall);

          await expect(instance.withdraw('100', isCall)).to.be.revertedWith(
            'liq lock 1d',
          );

          await ethers.provider.send('evm_increaseTime', [23 * 3600]);

          await expect(instance.withdraw('100', isCall)).to.be.revertedWith(
            'liq lock 1d',
          );
        });
      });
    });

    describe('#reassign', function () {
      describe('call option', () => {
        it('transfers freed capital to underwriter', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(lp2, amount, isCall);

          const oldBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          const contractSizeReassigned = oldBalance.div(ethers.constants.Two);

          const oldContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );
          const oldLPBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );

          const tx = await instance
            .connect(lp1)
            .reassign(shortTokenId, contractSizeReassigned, true);

          const {
            blockNumber: reassignBlockNumber,
            events,
            logs,
          } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(contractSizeReassigned)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );

          expect(newContractBalance).to.be.closeTo(
            oldContractBalance
              .sub(contractSizeReassigned)
              .add(baseCost)
              .add(feeCost)
              .sub(apyFeeRemaining),
            1,
          );
          expect(newLPBalance).to.be.closeTo(
            oldLPBalance
              .add(contractSizeReassigned)
              .sub(baseCost)
              .sub(feeCost)
              .add(apyFeeRemaining),
            1,
          );
        });

        it('assigns short position to new underwriter', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(lp2, amount, isCall);

          const oldBalanceLP1 = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldBalanceLP2 = await instance.callStatic.balanceOf(
            lp2.address,
            shortTokenId,
          );
          const oldSupply = await instance.callStatic.totalSupply(shortTokenId);

          const contractSizeReassigned = oldBalanceLP1.div(
            ethers.constants.Two,
          );

          await instance
            .connect(lp1)
            .reassign(shortTokenId, contractSizeReassigned, true);

          const newBalanceLP1 = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const newBalanceLP2 = await instance.callStatic.balanceOf(
            lp2.address,
            shortTokenId,
          );
          const newSupply = await instance.callStatic.totalSupply(shortTokenId);

          expect(newBalanceLP1).to.equal(
            oldBalanceLP1.sub(contractSizeReassigned),
          );
          expect(newBalanceLP2).to.equal(
            oldBalanceLP2.add(contractSizeReassigned),
          );
          expect(newSupply).to.equal(oldSupply);
        });

        it('deducts amount withdrawn from total TVL and user TVL', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(lp2, amount, isCall);

          const oldBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldSupply = await instance.callStatic.totalSupply(shortTokenId);
          await ethers.provider.send('evm_increaseTime', [24 * 3600]);
          await instance
            .connect(lp1)
            .withdraw(
              await instance.callStatic.balanceOf(
                lp1.address,
                getFreeLiqTokenId(isCall),
              ),
              isCall,
            );

          const contractSizeReassigned = oldBalance.div(ethers.constants.Two);

          const { underlyingTVL: oldUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(lp1)
            .reassign(shortTokenId, contractSizeReassigned, true);

          const {
            blockNumber: reassignBlockNumber,
            events,
            logs,
          } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(contractSizeReassigned)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.be.closeTo(
            oldUserTVL.sub(contractSizeReassigned).sub(apyFeeRemaining),
            1,
          );
          expect(newTotalTVL).to.be.closeTo(
            oldTotalTVL
              .sub(contractSizeReassigned)
              .add(baseCost)
              .sub(apyFeeRemaining)
              .sub(apyFeeRemaining),
            1,
          );
        });
      });

      describe('put option', () => {
        it('transfers freed capital to underwriter', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(
            lp2,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );

          const oldBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          const contractSizeReassigned = oldBalance.div(ethers.constants.Two);
          const tokenAmount = parseBase(
            formatUnderlying(contractSizeReassigned),
          ).mul(fixedToNumber(strike64x64));

          const oldContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );
          const oldLPBalance = await base.callStatic.balanceOf(lp1.address);

          const tx = await instance
            .connect(lp1)
            .reassign(shortTokenId, contractSizeReassigned, true);

          const {
            blockNumber: reassignBlockNumber,
            events,
            logs,
          } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await base.callStatic.balanceOf(lp1.address);

          expect(newContractBalance).to.be.closeTo(
            oldContractBalance
              .sub(tokenAmount)
              .add(baseCost)
              .add(feeCost)
              .sub(apyFeeRemaining),
            1,
          );
          expect(newLPBalance).to.be.closeTo(
            oldLPBalance
              .add(tokenAmount)
              .sub(baseCost)
              .sub(feeCost)
              .add(apyFeeRemaining),
            1,
          );
        });

        it('assigns short position to new underwriter', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(
            lp2,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );

          const oldBalanceLP1 = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldBalanceLP2 = await instance.callStatic.balanceOf(
            lp2.address,
            shortTokenId,
          );
          const oldSupply = await instance.callStatic.totalSupply(shortTokenId);

          const contractSizeReassigned = oldBalanceLP1.div(
            ethers.constants.Two,
          );

          await instance
            .connect(lp1)
            .reassign(shortTokenId, contractSizeReassigned, true);

          const newBalanceLP1 = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const newBalanceLP2 = await instance.callStatic.balanceOf(
            lp2.address,
            shortTokenId,
          );
          const newSupply = await instance.callStatic.totalSupply(shortTokenId);

          expect(newBalanceLP1).to.equal(
            oldBalanceLP1.sub(contractSizeReassigned),
          );
          expect(newBalanceLP2).to.equal(
            oldBalanceLP2.add(contractSizeReassigned),
          );
          expect(newSupply).to.equal(oldSupply);
        });

        it('deducts amount withdrawn from total TVL and user TVL', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(
            lp2,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );
          await ethers.provider.send('evm_increaseTime', [24 * 3600]);
          await instance
            .connect(lp1)
            .withdraw(
              await instance.callStatic.balanceOf(
                lp1.address,
                getFreeLiqTokenId(isCall),
              ),
              isCall,
            );

          const oldBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldSupply = await instance.callStatic.totalSupply(shortTokenId);

          const contractSizeReassigned = oldBalance.div(ethers.constants.Two);
          const tokenAmount = parseBase(
            formatUnderlying(contractSizeReassigned),
          ).mul(fixedToNumber(strike64x64));

          const { baseTVL: oldUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(lp1)
            .reassign(shortTokenId, contractSizeReassigned, true);

          const {
            blockNumber: reassignBlockNumber,
            events,
            logs,
          } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.be.closeTo(
            oldUserTVL.sub(tokenAmount).sub(apyFeeRemaining),
            1,
          );
          expect(newTotalTVL).to.be.closeTo(
            oldTotalTVL
              .sub(tokenAmount)
              .add(baseCost)
              .sub(apyFeeRemaining)
              .sub(apyFeeRemaining),
            2,
          );
        });
      });

      describe('reverts if', () => {
        it('contract size is less than minimum', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

          await p.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
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
            instance.connect(lp1).reassign(shortTokenId, '1', true),
          ).to.be.revertedWith('too small');
        });

        it('option is expired', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

          await p.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            strike64x64,
            isCall,
          );

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          const shortTokenBalance = await instance.balanceOf(
            lp1.address,
            shortTokenId,
          );

          await ethers.provider.send('evm_increaseTime', [11 * 24 * 3600]);

          await expect(
            instance
              .connect(lp1)
              .reassign(shortTokenId, shortTokenBalance, true),
          ).to.be.revertedWith('expired');
        });
      });
    });

    describe('#reassignBatch', function () {
      describe('call option', () => {
        it('transfers freed capital to underwriter', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(lp2, amount, isCall);

          const oldBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          const contractSizeReassigned = oldBalance.div(ethers.constants.Two);

          const oldContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );
          const oldLPBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );

          const tx = await instance
            .connect(lp1)
            .reassignBatch([shortTokenId], [contractSizeReassigned], true);

          const {
            blockNumber: reassignBlockNumber,
            events,
            logs,
          } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(contractSizeReassigned)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );

          expect(newContractBalance).to.be.closeTo(
            oldContractBalance
              .sub(contractSizeReassigned)
              .add(baseCost)
              .add(feeCost)
              .sub(apyFeeRemaining),
            1,
          );
          expect(newLPBalance).to.be.closeTo(
            oldLPBalance
              .add(contractSizeReassigned)
              .sub(baseCost)
              .sub(feeCost)
              .add(apyFeeRemaining),
            1,
          );
        });

        it('assigns short position to new underwriter', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(lp2, amount, isCall);

          const oldBalanceLP1 = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldBalanceLP2 = await instance.callStatic.balanceOf(
            lp2.address,
            shortTokenId,
          );
          const oldSupply = await instance.callStatic.totalSupply(shortTokenId);

          const contractSizeReassigned = oldBalanceLP1.div(
            ethers.constants.Two,
          );

          await instance
            .connect(lp1)
            .reassignBatch([shortTokenId], [contractSizeReassigned], true);

          const newBalanceLP1 = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const newBalanceLP2 = await instance.callStatic.balanceOf(
            lp2.address,
            shortTokenId,
          );
          const newSupply = await instance.callStatic.totalSupply(shortTokenId);

          expect(newBalanceLP1).to.equal(
            oldBalanceLP1.sub(contractSizeReassigned),
          );
          expect(newBalanceLP2).to.equal(
            oldBalanceLP2.add(contractSizeReassigned),
          );
          expect(newSupply).to.equal(oldSupply);
        });

        it('deducts amount withdrawn from total TVL and user TVL', async () => {
          const isCall = true;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(lp2, amount, isCall);

          const oldBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldSupply = await instance.callStatic.totalSupply(shortTokenId);
          await ethers.provider.send('evm_increaseTime', [24 * 3600]);
          await instance
            .connect(lp1)
            .withdraw(
              await instance.callStatic.balanceOf(
                lp1.address,
                getFreeLiqTokenId(isCall),
              ),
              isCall,
            );

          const contractSizeReassigned = oldBalance.div(ethers.constants.Two);

          const { underlyingTVL: oldUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(lp1)
            .reassignBatch([shortTokenId], [contractSizeReassigned], true);

          const {
            blockNumber: reassignBlockNumber,
            events,
            logs,
          } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(contractSizeReassigned)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.be.closeTo(
            oldUserTVL.sub(contractSizeReassigned).sub(apyFeeRemaining),
            1,
          );
          expect(newTotalTVL).to.be.closeTo(
            oldTotalTVL
              .sub(contractSizeReassigned)
              .add(baseCost)
              .sub(apyFeeRemaining)
              .sub(apyFeeRemaining),
            2,
          );
        });
      });

      describe('put option', () => {
        it('transfers freed capital to underwriter', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(
            lp2,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );

          const oldBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          const contractSizeReassigned = oldBalance.div(ethers.constants.Two);
          const tokenAmount = parseBase(
            formatUnderlying(contractSizeReassigned),
          ).mul(fixedToNumber(strike64x64));

          const oldContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );
          const oldLPBalance = await base.callStatic.balanceOf(lp1.address);

          const tx = await instance
            .connect(lp1)
            .reassignBatch([shortTokenId], [contractSizeReassigned], true);

          const {
            blockNumber: reassignBlockNumber,
            events,
            logs,
          } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await base.callStatic.balanceOf(lp1.address);

          expect(newContractBalance).to.be.closeTo(
            oldContractBalance
              .sub(tokenAmount)
              .add(baseCost)
              .add(feeCost)
              .sub(apyFeeRemaining),
            1,
          );
          expect(newLPBalance).to.be.closeTo(
            oldLPBalance
              .add(tokenAmount)
              .sub(baseCost)
              .sub(feeCost)
              .add(apyFeeRemaining),
            1,
          );
        });

        it('assigns short position to new underwriter', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(
            lp2,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );

          const oldBalanceLP1 = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldBalanceLP2 = await instance.callStatic.balanceOf(
            lp2.address,
            shortTokenId,
          );
          const oldSupply = await instance.callStatic.totalSupply(shortTokenId);

          const contractSizeReassigned = oldBalanceLP1.div(
            ethers.constants.Two,
          );

          await instance
            .connect(lp1)
            .reassignBatch([shortTokenId], [contractSizeReassigned], true);

          const newBalanceLP1 = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const newBalanceLP2 = await instance.callStatic.balanceOf(
            lp2.address,
            shortTokenId,
          );
          const newSupply = await instance.callStatic.totalSupply(shortTokenId);

          expect(newBalanceLP1).to.equal(
            oldBalanceLP1.sub(contractSizeReassigned),
          );
          expect(newBalanceLP2).to.equal(
            oldBalanceLP2.add(contractSizeReassigned),
          );
          expect(newSupply).to.equal(oldSupply);
        });

        it('deducts amount withdrawn from total TVL and user TVL', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

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

          await p.depositLiquidity(
            lp2,
            parseBase(formatUnderlying(amount)).mul(fixedToNumber(strike64x64)),
            isCall,
          );
          await ethers.provider.send('evm_increaseTime', [24 * 3600]);
          await instance
            .connect(lp1)
            .withdraw(
              await instance.callStatic.balanceOf(
                lp1.address,
                getFreeLiqTokenId(isCall),
              ),
              isCall,
            );

          const oldBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );
          const oldSupply = await instance.callStatic.totalSupply(shortTokenId);

          const contractSizeReassigned = oldBalance.div(ethers.constants.Two);
          const tokenAmount = parseBase(
            formatUnderlying(contractSizeReassigned),
          ).mul(fixedToNumber(strike64x64));

          const { baseTVL: oldUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(lp1)
            .reassignBatch([shortTokenId], [contractSizeReassigned], true);

          const {
            blockNumber: reassignBlockNumber,
            events,
            logs,
          } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const purchaseEvent = events!.find((e) => e.event == 'Purchase')!;

          const { baseCost, feeCost } = purchaseEvent.args!;

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.be.closeTo(
            oldUserTVL.sub(tokenAmount).sub(apyFeeRemaining),
            1,
          );
          expect(newTotalTVL).to.be.closeTo(
            oldTotalTVL
              .sub(tokenAmount)
              .add(baseCost)
              .sub(apyFeeRemaining)
              .sub(apyFeeRemaining),
            1,
          );
        });
      });

      describe('reverts if', () => {
        it('contract size is less than minimum', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

          await p.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
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
            instance.connect(lp1).reassignBatch([shortTokenId], ['1'], true),
          ).to.be.revertedWith('too small');
        });

        it('option is expired', async () => {
          const isCall = false;
          const maturity = await getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall, 2000));

          await p.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            strike64x64,
            isCall,
          );

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          const shortTokenBalance = await instance.balanceOf(
            lp1.address,
            shortTokenId,
          );

          await ethers.provider.send('evm_increaseTime', [11 * 24 * 3600]);

          await expect(
            instance
              .connect(lp1)
              .reassignBatch([shortTokenId], [shortTokenBalance], true),
          ).to.be.revertedWith('expired');
        });
      });
    });

    describe('#withdrawFees', () => {
      it('todo');
    });

    describe('#annihilate', () => {
      describe('call option', () => {
        it('burns corresponding long and short tokens held by sender', async () => {
          const isCall = true;
          const maturity = await getMaturity(30);
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

          await instance
            .connect(lp1)
            .writeFrom(
              lp1.address,
              lp1.address,
              maturity,
              strike64x64,
              amount,
              isCall,
            );

          await ethers.provider.send('evm_increaseTime', [23 * 3600]);

          const contractSizeAnnihilated = amount.div(ethers.constants.Two);

          const oldLongTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            longTokenId,
          );
          const oldShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          await instance
            .connect(lp1)
            .annihilate(shortTokenId, contractSizeAnnihilated, true);

          const newLongTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            longTokenId,
          );
          const newShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          expect(newLongTokenBalance).to.equal(
            oldLongTokenBalance.sub(contractSizeAnnihilated),
          );
          expect(newShortTokenBalance).to.equal(
            oldShortTokenBalance.sub(contractSizeAnnihilated),
          );
        });

        it('transfers freed capital to sender', async () => {
          const isCall = true;
          const maturity = await getMaturity(30);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await instance
            .connect(lp1)
            .writeFrom(
              lp1.address,
              lp1.address,
              maturity,
              strike64x64,
              amount,
              isCall,
            );

          await ethers.provider.send('evm_increaseTime', [23 * 3600]);

          const contractSizeAnnihilated = amount.div(ethers.constants.Two);

          const oldContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );
          const oldLPBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );

          const tx = await instance
            .connect(lp1)
            .annihilate(shortTokenId, contractSizeAnnihilated, true);

          const { blockNumber: reassignBlockNumber } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(contractSizeAnnihilated)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );

          expect(newContractBalance).to.be.closeTo(
            oldContractBalance
              .sub(contractSizeAnnihilated)
              .sub(apyFeeRemaining),
            1,
          );
          expect(newLPBalance).to.be.closeTo(
            oldLPBalance.add(contractSizeAnnihilated).add(apyFeeRemaining),
            1,
          );
        });

        it('deducts amount annihilated from total TVL and user TVL', async () => {
          const isCall = true;
          const maturity = await getMaturity(30);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await instance
            .connect(lp1)
            .writeFrom(
              lp1.address,
              lp1.address,
              maturity,
              strike64x64,
              amount,
              isCall,
            );

          await ethers.provider.send('evm_increaseTime', [23 * 3600]);

          const contractSizeAnnihilated = amount.div(ethers.constants.Two);

          const { underlyingTVL: oldUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(lp1)
            .annihilate(shortTokenId, contractSizeAnnihilated, true);

          const { blockNumber: annihilateBlockNumber } = await tx.wait();
          const { timestamp: annihilateTimestamp } =
            await ethers.provider.getBlock(annihilateBlockNumber);

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(annihilateTimestamp))
            .mul(contractSizeAnnihilated)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.be.closeTo(
            oldUserTVL.sub(contractSizeAnnihilated),
            1,
          );
          expect(newTotalTVL).to.be.closeTo(
            oldTotalTVL.sub(contractSizeAnnihilated),
            1,
          );
        });
      });

      describe('put option', () => {
        it('burns corresponding long and short tokens held by sender', async () => {
          const isCall = false;
          const maturity = await getMaturity(30);
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

          await instance
            .connect(lp1)
            .writeFrom(
              lp1.address,
              lp1.address,
              maturity,
              strike64x64,
              amount,
              isCall,
            );

          await ethers.provider.send('evm_increaseTime', [23 * 3600]);

          const contractSizeAnnihilated = amount.div(ethers.constants.Two);

          const oldLongTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            longTokenId,
          );
          const oldShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          await instance
            .connect(lp1)
            .annihilate(shortTokenId, contractSizeAnnihilated, true);

          const newLongTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            longTokenId,
          );
          const newShortTokenBalance = await instance.callStatic.balanceOf(
            lp1.address,
            shortTokenId,
          );

          expect(newLongTokenBalance).to.equal(
            oldLongTokenBalance.sub(contractSizeAnnihilated),
          );
          expect(newShortTokenBalance).to.equal(
            oldShortTokenBalance.sub(contractSizeAnnihilated),
          );
        });

        it('transfers freed capital to sender', async () => {
          const isCall = false;
          const maturity = await getMaturity(30);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await instance
            .connect(lp1)
            .writeFrom(
              lp1.address,
              lp1.address,
              maturity,
              strike64x64,
              amount,
              isCall,
            );

          await ethers.provider.send('evm_increaseTime', [23 * 3600]);

          const contractSizeAnnihilated = amount.div(ethers.constants.Two);
          const tokenAmount = parseBase(
            formatUnderlying(contractSizeAnnihilated),
          ).mul(fixedToNumber(strike64x64));

          const oldContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );
          const oldLPBalance = await base.callStatic.balanceOf(lp1.address);

          const tx = await instance
            .connect(lp1)
            .annihilate(shortTokenId, contractSizeAnnihilated, true);

          const { blockNumber: annihilateBlockNumber } = await tx.wait();
          const { timestamp: annihilateTimestamp } =
            await ethers.provider.getBlock(annihilateBlockNumber);

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(annihilateTimestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await base.callStatic.balanceOf(lp1.address);

          expect(newContractBalance).to.be.closeTo(
            oldContractBalance.sub(tokenAmount).sub(apyFeeRemaining),
            1,
          );
          expect(newLPBalance).to.be.closeTo(
            oldLPBalance.add(tokenAmount).add(apyFeeRemaining),
            1,
          );
        });

        it('deducts amount annihilated from total TVL and user TVL', async () => {
          const isCall = false;
          const maturity = await getMaturity(30);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await instance
            .connect(lp1)
            .writeFrom(
              lp1.address,
              lp1.address,
              maturity,
              strike64x64,
              amount,
              isCall,
            );

          await ethers.provider.send('evm_increaseTime', [23 * 3600]);

          const contractSizeAnnihilated = amount.div(ethers.constants.Two);
          const tokenAmount = parseBase(
            formatUnderlying(contractSizeAnnihilated),
          ).mul(fixedToNumber(strike64x64));

          const { baseTVL: oldUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: oldTotalTVL } =
            await instance.callStatic.getTotalTVL();

          const tx = await instance
            .connect(lp1)
            .annihilate(shortTokenId, contractSizeAnnihilated, true);

          const { blockNumber: annihilateBlockNumber } = await tx.wait();
          const { timestamp: annihilateTimestamp } =
            await ethers.provider.getBlock(annihilateBlockNumber);

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(annihilateTimestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(apyFeeRate.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.be.closeTo(oldUserTVL.sub(tokenAmount), 1);
          expect(newTotalTVL).to.be.closeTo(oldTotalTVL.sub(tokenAmount), 1);
        });
      });

      describe('reverts if', () => {
        it('sender has insufficient long token balance', async () => {
          const isCall = false;
          const maturity = await getMaturity(30);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          await instance
            .connect(lp1)
            .writeFrom(
              lp1.address,
              lp1.address,
              maturity,
              strike64x64,
              amount,
              isCall,
            );

          await instance
            .connect(lp1)
            .safeTransferFrom(
              lp1.address,
              lp2.address,
              longTokenId,
              ethers.constants.One,
              '0x',
            );

          await expect(
            instance.connect(lp1).annihilate(longTokenId, amount, true),
          ).to.be.revertedWithCustomError(
            instance,
            'ERC1155Base__BurnExceedsBalance',
          );
        });

        it('sender has insufficient short token balance', async () => {
          const isCall = false;
          const maturity = await getMaturity(30);
          const strike = getStrike(isCall, 2000);
          const strike64x64 = fixedFromFloat(strike);
          const amount = parseUnderlying('1');

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          await instance
            .connect(lp1)
            .writeFrom(
              lp1.address,
              lp1.address,
              maturity,
              strike64x64,
              amount,
              isCall,
            );

          await instance
            .connect(lp1)
            .safeTransferFrom(
              lp1.address,
              lp2.address,
              shortTokenId,
              ethers.constants.One,
              '0x',
            );

          await expect(
            instance.connect(lp1).annihilate(shortTokenId, amount, true),
          ).to.be.revertedWithPanic('0x11');
        });
      });
    });

    describe('#claimRewards', () => {
      it('todo');
    });

    describe('#claimRewards', () => {
      it('todo');
    });

    describe('#updateMiningPools', () => {
      it('todo');
    });
  });
}
