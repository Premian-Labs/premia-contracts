import { ethers } from 'hardhat';
import { expect } from 'chai';
import { IPool, PoolIO__factory, ERC20Mock } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
  getOptionTokenIds,
} from '@premia/utils';

import {
  createUniswapPair,
  depositUniswapLiquidity,
  IUniswap,
} from '../../test/utils/uniswap';

import {
  FEE_APY,
  ONE_YEAR,
  DECIMALS_BASE,
  DECIMALS_UNDERLYING,
  formatUnderlying,
  formatBase,
  parseBase,
  parseOption,
  parseUnderlying,
  getFreeLiqTokenId,
  getReservedLiqTokenId,
  getShort,
  getLong,
  getStrike,
  getMaturity,
  PoolUtil,
} from '../../test/pool/PoolUtil';

interface PoolIOBehaviorArgs {
  deploy: () => Promise<IPool>;
  getBase: () => Promise<ERC20Mock>;
  getUnderlying: () => Promise<ERC20Mock>;
  getPoolUtil: () => Promise<PoolUtil>;
  getUniswap: () => Promise<IUniswap>;
}

export function describeBehaviorOfPoolIO({
  deploy,
  getBase,
  getUnderlying,
  getPoolUtil,
  getUniswap,
}: PoolIOBehaviorArgs) {
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
    });

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

        it('should revert if pool TVL exceeds limit', async () => {
          const signers = (await ethers.getSigners()).slice(0, 10);

          for (const signer of signers) {
            await instance
              .connect(signer)
              .deposit(parseUnderlying((1000000 / 10).toString()), true);
          }

          await expect(instance.deposit(1, true)).to.be.revertedWith(
            'pool deposit cap reached',
          );
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
          it('should successfully swaps tokens and purchase an option', async () => {
            const mintAmount = parseOption(
              !isCall ? '1000' : '100000',
              !isCall,
            );

            const amount = isCall
              ? parseOption('0.1', isCall)
              : parseOption('1000', isCall);

            await instance
              .connect(buyer)
              .swapAndDeposit(
                amount,
                isCall,
                0,
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

            expect(
              await instance.balanceOf(
                buyer.address,
                getFreeLiqTokenId(isCall),
              ),
            ).to.eq(amount);
          });

          it('should successfully swaps tokens and purchase an option with ETH', async () => {
            const mintAmount = parseOption(
              !isCall ? '1000' : '100000',
              !isCall,
            );

            const amount = isCall
              ? parseOption('0.1', isCall)
              : parseOption('1000', isCall);

            await instance
              .connect(buyer)
              .swapAndDeposit(
                amount,
                isCall,
                0,
                0,
                isCall
                  ? [uniswap.weth.address, p.underlying.address]
                  : [uniswap.weth.address, p.base.address],
                false,
                { value: ethers.utils.parseEther('2') },
              );

            expect(
              await instance.balanceOf(
                buyer.address,
                getFreeLiqTokenId(isCall),
              ),
            ).to.eq(amount);
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
          it('should return underlying tokens withdrawn by sender', async () => {
            await p.depositLiquidity(owner, 100, isCall);
            expect(await p.getToken(isCall).balanceOf(owner.address)).to.eq(0);

            await ethers.provider.send('evm_increaseTime', [24 * 3600 + 60]);

            await instance.withdraw('100', isCall);
            expect(await p.getToken(isCall).balanceOf(owner.address)).to.eq(
              100,
            );
            expect(
              await instance.balanceOf(
                owner.address,
                getFreeLiqTokenId(isCall),
              ),
            ).to.eq(0);
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
            .reassign(shortTokenId, contractSizeReassigned);

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
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );

          expect(newContractBalance).to.almost(
            oldContractBalance
              .sub(contractSizeReassigned)
              .add(baseCost)
              .add(feeCost)
              .sub(apyFeeRemaining),
          );
          expect(newLPBalance).to.almost(
            oldLPBalance
              .add(contractSizeReassigned)
              .sub(baseCost)
              .sub(feeCost)
              .add(apyFeeRemaining),
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
            .reassign(shortTokenId, contractSizeReassigned);

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
            .reassign(shortTokenId, contractSizeReassigned);

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
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.almost(
            oldUserTVL.sub(contractSizeReassigned).sub(apyFeeRemaining),
          );
          expect(newTotalTVL).to.almost(
            oldTotalTVL
              .sub(contractSizeReassigned)
              .add(baseCost)
              .sub(apyFeeRemaining)
              .sub(apyFeeRemaining),
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
            .reassign(shortTokenId, contractSizeReassigned);

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
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await base.callStatic.balanceOf(lp1.address);

          expect(newContractBalance).to.almost(
            oldContractBalance
              .sub(tokenAmount)
              .add(baseCost)
              .add(feeCost)
              .sub(apyFeeRemaining),
          );
          expect(newLPBalance).to.almost(
            oldLPBalance
              .add(tokenAmount)
              .sub(baseCost)
              .sub(feeCost)
              .add(apyFeeRemaining),
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
            .reassign(shortTokenId, contractSizeReassigned);

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
            .reassign(shortTokenId, contractSizeReassigned);

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
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.almost(
            oldUserTVL.sub(tokenAmount).sub(apyFeeRemaining),
          );
          expect(newTotalTVL).to.almost(
            oldTotalTVL
              .sub(tokenAmount)
              .add(baseCost)
              .sub(apyFeeRemaining)
              .sub(apyFeeRemaining),
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
            instance.connect(lp1).reassign(shortTokenId, '1'),
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
            instance.connect(lp1).reassign(shortTokenId, shortTokenBalance),
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
            .reassignBatch([shortTokenId], [contractSizeReassigned]);

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
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );

          expect(newContractBalance).to.almost(
            oldContractBalance
              .sub(contractSizeReassigned)
              .add(baseCost)
              .add(feeCost)
              .sub(apyFeeRemaining),
          );
          expect(newLPBalance).to.almost(
            oldLPBalance
              .add(contractSizeReassigned)
              .sub(baseCost)
              .sub(feeCost)
              .add(apyFeeRemaining),
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
            .reassignBatch([shortTokenId], [contractSizeReassigned]);

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
            .reassignBatch([shortTokenId], [contractSizeReassigned]);

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
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.almost(
            oldUserTVL.sub(contractSizeReassigned).sub(apyFeeRemaining),
          );
          expect(newTotalTVL).to.almost(
            oldTotalTVL
              .sub(contractSizeReassigned)
              .add(baseCost)
              .sub(apyFeeRemaining)
              .sub(apyFeeRemaining),
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
            .reassignBatch([shortTokenId], [contractSizeReassigned]);

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
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await base.callStatic.balanceOf(lp1.address);

          expect(newContractBalance).to.almost(
            oldContractBalance
              .sub(tokenAmount)
              .add(baseCost)
              .add(feeCost)
              .sub(apyFeeRemaining),
          );
          expect(newLPBalance).to.almost(
            oldLPBalance
              .add(tokenAmount)
              .sub(baseCost)
              .sub(feeCost)
              .add(apyFeeRemaining),
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
            .reassignBatch([shortTokenId], [contractSizeReassigned]);

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
            .reassignBatch([shortTokenId], [contractSizeReassigned]);

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
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.almost(
            oldUserTVL.sub(tokenAmount).sub(apyFeeRemaining),
          );
          expect(newTotalTVL).to.almost(
            oldTotalTVL
              .sub(tokenAmount)
              .add(baseCost)
              .sub(apyFeeRemaining)
              .sub(apyFeeRemaining),
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
            instance.connect(lp1).reassignBatch([shortTokenId], ['1']),
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
              .reassignBatch([shortTokenId], [shortTokenBalance]),
          ).to.be.revertedWith('expired');
        });
      });
    });

    describe('#withdrawAllAndReassignBatch', () => {
      it('todo');
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
            .annihilate(shortTokenId, contractSizeAnnihilated);

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
            .annihilate(shortTokenId, contractSizeAnnihilated);

          const { blockNumber: reassignBlockNumber } = await tx.wait();
          const { timestamp: reassignTimestamp } =
            await ethers.provider.getBlock(reassignBlockNumber);

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(reassignTimestamp))
            .mul(contractSizeAnnihilated)
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await underlying.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await underlying.callStatic.balanceOf(
            lp1.address,
          );

          expect(newContractBalance).to.almost(
            oldContractBalance
              .sub(contractSizeAnnihilated)
              .sub(apyFeeRemaining),
          );
          expect(newLPBalance).to.almost(
            oldLPBalance.add(contractSizeAnnihilated).add(apyFeeRemaining),
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
            .annihilate(shortTokenId, contractSizeAnnihilated);

          const { blockNumber: annihilateBlockNumber } = await tx.wait();
          const { timestamp: annihilateTimestamp } =
            await ethers.provider.getBlock(annihilateBlockNumber);

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(annihilateTimestamp))
            .mul(contractSizeAnnihilated)
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { underlyingTVL: newUserTVL } =
            await instance.callStatic.getUserTVL(lp1.address);
          const { underlyingTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.almost(oldUserTVL.sub(contractSizeAnnihilated));
          expect(newTotalTVL).to.almost(
            oldTotalTVL.sub(contractSizeAnnihilated),
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
            .annihilate(shortTokenId, contractSizeAnnihilated);

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
            .annihilate(shortTokenId, contractSizeAnnihilated);

          const { blockNumber: annihilateBlockNumber } = await tx.wait();
          const { timestamp: annihilateTimestamp } =
            await ethers.provider.getBlock(annihilateBlockNumber);

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(annihilateTimestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const newContractBalance = await base.callStatic.balanceOf(
            instance.address,
          );
          const newLPBalance = await base.callStatic.balanceOf(lp1.address);

          expect(newContractBalance).to.almost(
            oldContractBalance.sub(tokenAmount).sub(apyFeeRemaining),
          );
          expect(newLPBalance).to.almost(
            oldLPBalance.add(tokenAmount).add(apyFeeRemaining),
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
            .annihilate(shortTokenId, contractSizeAnnihilated);

          const { blockNumber: annihilateBlockNumber } = await tx.wait();
          const { timestamp: annihilateTimestamp } =
            await ethers.provider.getBlock(annihilateBlockNumber);

          const apyFeeRemaining = maturity
            .sub(ethers.BigNumber.from(annihilateTimestamp))
            .mul(tokenAmount)
            .mul(ethers.utils.parseEther(FEE_APY.toString()))
            .div(ethers.utils.parseEther(ONE_YEAR.toString()));

          const { baseTVL: newUserTVL } = await instance.callStatic.getUserTVL(
            lp1.address,
          );
          const { baseTVL: newTotalTVL } =
            await instance.callStatic.getTotalTVL();

          expect(newUserTVL).to.almost(oldUserTVL.sub(tokenAmount));
          expect(newTotalTVL).to.almost(oldTotalTVL.sub(tokenAmount));
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
            instance.connect(lp1).annihilate(longTokenId, amount),
          ).to.be.revertedWith('ERC1155: burn amount exceeds balances');
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
            instance.connect(lp1).annihilate(shortTokenId, amount),
          ).to.be.revertedWith('ERC1155: burn amount exceeds balances');
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

    describe('#increaseUserTVL', () => {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('increases TVL of given users by given amounts', async () => {
            await p.depositLiquidity(lp1, parseOption('1', true), isCall);
            await p.depositLiquidity(lp2, parseOption('1', true), isCall);

            const amount1 = ethers.constants.One;
            const amount2 = ethers.constants.Two;

            const tvlKey = isCall ? 'underlyingTVL' : 'baseTVL';

            const oldUserTVL1 = (
              await instance.callStatic.getUserTVL(lp1.address)
            )[tvlKey];
            const oldUserTVL2 = (
              await instance.callStatic.getUserTVL(lp2.address)
            )[tvlKey];

            await PoolIO__factory.connect(
              instance.address,
              owner,
            ).increaseUserTVL(
              [lp1.address, lp2.address],
              [amount1, amount2],
              isCall,
            );

            const newUserTVL1 = (
              await instance.callStatic.getUserTVL(lp1.address)
            )[tvlKey];
            const newUserTVL2 = (
              await instance.callStatic.getUserTVL(lp2.address)
            )[tvlKey];

            expect(newUserTVL1).to.equal(oldUserTVL1.add(amount1));
            expect(newUserTVL2).to.equal(oldUserTVL2.add(amount2));
          });
        });
      }

      describe('reverts if', () => {
        it('sender is not protocol owner', async () => {
          await expect(
            PoolIO__factory.connect(instance.address, lp1).increaseUserTVL(
              [lp1.address, lp2.address],
              [ethers.constants.Zero, ethers.constants.Zero],
              false,
            ),
          ).to.be.revertedWith('Not protocol owner');
        });
      });
    });

    describe('#decreaseUserTVL', () => {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('decreases TVL of given users by given amounts', async () => {
            await p.depositLiquidity(lp1, parseOption('1', true), isCall);
            await p.depositLiquidity(lp2, parseOption('1', true), isCall);

            const amount1 = ethers.constants.One;
            const amount2 = ethers.constants.Two;

            const tvlKey = isCall ? 'underlyingTVL' : 'baseTVL';

            const oldUserTVL1 = (
              await instance.callStatic.getUserTVL(lp1.address)
            )[tvlKey];
            const oldUserTVL2 = (
              await instance.callStatic.getUserTVL(lp2.address)
            )[tvlKey];

            await PoolIO__factory.connect(
              instance.address,
              owner,
            ).decreaseUserTVL(
              [lp1.address, lp2.address],
              [amount1, amount2],
              isCall,
            );

            const newUserTVL1 = (
              await instance.callStatic.getUserTVL(lp1.address)
            )[tvlKey];
            const newUserTVL2 = (
              await instance.callStatic.getUserTVL(lp2.address)
            )[tvlKey];

            expect(newUserTVL1).to.equal(oldUserTVL1.sub(amount1));
            expect(newUserTVL2).to.equal(oldUserTVL2.sub(amount2));
          });
        });
      }

      describe('reverts if', () => {
        it('sender is not protocol owner', async () => {
          await expect(
            PoolIO__factory.connect(instance.address, lp1).decreaseUserTVL(
              [lp1.address, lp2.address],
              [ethers.constants.Zero, ethers.constants.Zero],
              false,
            ),
          ).to.be.revertedWith('Not protocol owner');
        });
      });
    });
  });
}
