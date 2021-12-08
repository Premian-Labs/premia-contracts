import { ethers } from 'hardhat';
import { expect } from 'chai';
import { IPool } from '../../typechain';
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
  DECIMALS_BASE,
  DECIMALS_UNDERLYING,
  parseBase,
  parseOption,
  parseUnderlying,
  PoolUtil,
} from '../../test/pool/PoolUtil';

interface PoolIOBehaviorArgs {
  deploy: () => Promise<IPool>;
  getPoolUtil: () => Promise<PoolUtil>;
  getUniswap: () => Promise<IUniswap>;
}

export function describeBehaviorOfPoolIO({
  deploy,
  getPoolUtil,
  getUniswap,
}: PoolIOBehaviorArgs) {
  describe('::PoolIO', () => {
    let owner: SignerWithAddress;
    let buyer: SignerWithAddress;
    let lp1: SignerWithAddress;
    let lp2: SignerWithAddress;
    let instance: IPool;
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
          await p.underlying.mint(owner.address, 100);
          await p.underlying.approve(
            instance.address,
            ethers.constants.MaxUint256,
          );
          await expect(() =>
            instance.deposit('100', true),
          ).to.changeTokenBalance(p.underlying, owner, -100);
          expect(
            await instance.balanceOf(owner.address, p.getFreeLiqTokenId(true)),
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
            await p.poolWeth.balanceOf(
              owner.address,
              p.getFreeLiqTokenId(true),
            ),
          ).to.eq(350);
        });

        it('should revert if user send ETH with a token deposit', async () => {
          await p.underlying.mint(owner.address, 100);
          await p.underlying.approve(
            instance.address,
            ethers.constants.MaxUint256,
          );
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
            await p.underlying
              .connect(signer)
              .mint(signer.address, parseUnderlying((1000000).toString()));
            await p.underlying
              .connect(signer)
              .approve(instance.address, ethers.constants.MaxUint256);
            await instance
              .connect(signer)
              .deposit(parseUnderlying((1000000 / 10).toString()), true);
          }

          await expect(instance.deposit(1, true)).to.be.revertedWith(
            'pool deposit cap reached',
          );
        });
      });

      describe('put', () => {
        it('should grant sender share tokens with ERC20 deposit', async () => {
          await p.base.mint(owner.address, 100);
          await p.base.approve(instance.address, ethers.constants.MaxUint256);
          await expect(() =>
            instance.deposit('100', false),
          ).to.changeTokenBalance(p.base, owner, -100);
          expect(
            await instance.balanceOf(owner.address, p.getFreeLiqTokenId(false)),
          ).to.eq(100);
        });
      });
    });

    describe('#swapAndDeposit', function () {
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

            const mintAmount = parseOption(
              !isCall ? '1000' : '100000',
              !isCall,
            );
            await p.getToken(!isCall).mint(buyer.address, mintAmount);
            await p
              .getToken(isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);
            await p
              .getToken(!isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);

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
                p.getFreeLiqTokenId(isCall),
              ),
            ).to.eq(amount);
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

            const mintAmount = parseOption(
              !isCall ? '1000' : '100000',
              !isCall,
            );

            await p.getToken(!isCall).mint(buyer.address, mintAmount);
            await p
              .getToken(isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);
            await p
              .getToken(!isCall)
              .connect(buyer)
              .approve(instance.address, ethers.constants.MaxUint256);

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
                p.getFreeLiqTokenId(isCall),
              ),
            ).to.eq(amount);
          });
        });
      }
    });

    describe('#withdraw', function () {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('should fail withdrawing if < 1 day after deposit', async () => {
            await p.depositLiquidity(owner, 100, isCall);

            await expect(instance.withdraw('100', isCall)).to.be.revertedWith(
              'liq lock 1d',
            );

            await ethers.provider.send('evm_increaseTime', [23 * 3600]);

            await expect(instance.withdraw('100', isCall)).to.be.revertedWith(
              'liq lock 1d',
            );
          });

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
                p.getFreeLiqTokenId(isCall),
              ),
            ).to.eq(0);
          });

          it('should successfully withdraw reserved liquidity', async () => {
            // ToDo
            expect(false);
          });
        });
      }
    });

    describe('#reassign', function () {
      for (const isCall of [true, false]) {
        describe(isCall ? 'call' : 'put', () => {
          it('should revert if contract size is less than minimum', async () => {
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
              instance.connect(lp1).reassign(shortTokenId, '1'),
            ).to.be.revertedWith('too small');
          });

          it('should revert if option is expired', async () => {
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

            const shortTokenBalance = await instance.balanceOf(
              lp1.address,
              shortTokenId,
            );

            await ethers.provider.send('evm_increaseTime', [11 * 24 * 3600]);

            await expect(
              instance.connect(lp1).reassign(shortTokenId, shortTokenBalance),
            ).to.be.revertedWith('expired');
          });

          it('should successfully reassign option to another LP', async () => {
            const maturity = await p.getMaturity(10);
            const strike64x64 = fixedFromFloat(p.getStrike(isCall, 2000));
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

            await ethers.provider.send('evm_increaseTime', [25 * 3600]);

            const shortTokenId = formatTokenId({
              tokenType: p.getShort(isCall),
              maturity,
              strike64x64,
            });

            const shortTokenBalance = await instance.balanceOf(
              lp1.address,
              shortTokenId,
            );

            await instance
              .connect(lp1)
              .withdrawAllAndReassignBatch(
                isCall,
                [shortTokenId],
                [shortTokenBalance],
              );

            expect(
              await instance.balanceOf(
                lp1.address,
                p.getFreeLiqTokenId(isCall),
              ),
            ).to.eq(0);
            expect(await instance.balanceOf(lp1.address, shortTokenId)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp2.address, shortTokenId)).to.eq(
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
          instance.connect(lp1).reassignBatch([shortTokenId], ['1']),
        ).to.be.revertedWith('too small');
      });
    });

    describe('#withdrawAllAndReassignBatch', () => {
      it('todo');
    });

    describe('#withdrawFees', () => {
      it('todo');
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

            expect(await instance.balanceOf(lp1.address, tokenIds.long)).to.eq(
              amount,
            );
            expect(await instance.balanceOf(lp1.address, tokenIds.short)).to.eq(
              amount,
            );
            expect(await p.getToken(isCall).balanceOf(lp1.address)).to.eq(0);

            await instance.connect(lp1).annihilate(tokenIds.short, amount);

            expect(await instance.balanceOf(lp1.address, tokenIds.long)).to.eq(
              0,
            );
            expect(await instance.balanceOf(lp1.address, tokenIds.short)).to.eq(
              0,
            );
            expect(await p.getToken(isCall).balanceOf(lp1.address)).to.eq(
              isCall ? amount : parseBase('2'),
            );
          });
        });
      }
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
