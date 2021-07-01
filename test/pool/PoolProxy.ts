import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  ManagedProxyOwnable,
  ManagedProxyOwnable__factory,
  OptionMath,
  OptionMath__factory,
  PoolMock,
  PoolMock__factory,
  Premia,
  Premia__factory,
  ProxyManager__factory,
  WETH9,
  WETH9__factory,
} from '../../typechain';

import { describeBehaviorOfManagedProxyOwnable } from '@solidstate/spec';
import { describeBehaviorOfPool } from './Pool.behavior';
import chai, { expect } from 'chai';
import { increaseTimestamp, resetHardhat, setTimestamp } from '../utils/evm';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { hexlify, hexZeroPad, parseUnits } from 'ethers/lib/utils';
import {
  DECIMALS_BASE,
  DECIMALS_UNDERLYING,
  formatOption,
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

chai.use(chaiAlmost(0.02));

const SYMBOL_BASE = 'SYMBOL_BASE';
const SYMBOL_UNDERLYING = 'SYMBOL_UNDERLYING';

describe('PoolProxy', function () {
  let owner: SignerWithAddress;
  let lp1: SignerWithAddress;
  let lp2: SignerWithAddress;
  let buyer: SignerWithAddress;
  let thirdParty: SignerWithAddress;

  let premia: Premia;
  let proxy: ManagedProxyOwnable;
  let optionMath: OptionMath;
  let pool: PoolMock;
  let poolWeth: PoolMock;
  let base: ERC20Mock;
  let underlying: ERC20Mock;
  let underlyingWeth: WETH9;
  let poolUtil: PoolUtil;
  let baseOracle: MockContract;
  let underlyingOracle: MockContract;

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

  const getToken = (isCall: boolean) => {
    return isCall ? underlying : base;
  };

  const getLong = (isCall: boolean) => {
    return isCall ? TokenType.LongCall : TokenType.LongPut;
  };

  const getShort = (isCall: boolean) => {
    return isCall ? TokenType.ShortCall : TokenType.ShortPut;
  };

  const getStrike = (isCall: boolean) => {
    return isCall ? spotPrice * 1.25 : spotPrice * 0.75;
  };

  const getMaxCost = (
    baseCost64x64: BigNumber,
    feeCost64x64: BigNumber,
    isCall: boolean,
  ) => {
    if (isCall) {
      return parseUnderlying(
        (
          (fixedToNumber(baseCost64x64) + fixedToNumber(feeCost64x64)) *
          1.03
        ).toString(),
      );
    } else {
      return parseBase(
        (
          (fixedToNumber(baseCost64x64) + fixedToNumber(feeCost64x64)) *
          1.03
        ).toString(),
      );
    }
  };

  const getFreeLiqTokenId = (isCall: boolean) => {
    if (isCall) {
      return formatTokenId({
        tokenType: TokenType.UnderlyingFreeLiq,
        maturity: BigNumber.from(0),
        strike64x64: BigNumber.from(0),
      });
    } else {
      return formatTokenId({
        tokenType: TokenType.BaseFreeLiq,
        maturity: BigNumber.from(0),
        strike64x64: BigNumber.from(0),
      });
    }
  };

  const spotPrice = 2000;

  const setUnderlyingPrice = async (price: BigNumber) => {
    await underlyingOracle.mock.latestAnswer.returns(price);
  };

  beforeEach(async function () {
    await resetHardhat();
    [owner, lp1, lp2, buyer, thirdParty] = await ethers.getSigners();

    //

    const erc20Factory = new ERC20Mock__factory(owner);

    base = await erc20Factory.deploy(SYMBOL_BASE, DECIMALS_BASE);
    await base.deployed();
    underlying = await erc20Factory.deploy(
      SYMBOL_UNDERLYING,
      DECIMALS_UNDERLYING,
    );
    await underlying.deployed();
    underlyingWeth = await new WETH9__factory(owner).deploy();

    //

    const optionMath = await new OptionMath__factory(owner).deploy();

    const poolImp = await new PoolMock__factory(
      { __$430b703ddf4d641dc7662832950ed9cf8d$__: optionMath.address },
      owner,
    ).deploy(underlyingWeth.address);

    const facetCuts = [await new ProxyManager__factory(owner).deploy()].map(
      function (f) {
        return {
          target: f.address,
          action: 0,
          selectors: Object.keys(f.interface.functions).map((fn) =>
            f.interface.getSighash(fn),
          ),
        };
      },
    );

    premia = await new Premia__factory(owner).deploy(poolImp.address);

    await premia.diamondCut(facetCuts, ethers.constants.AddressZero, '0x');

    //

    const manager = ProxyManager__factory.connect(premia.address, owner);

    baseOracle = await deployMockContract(owner, [
      'function latestAnswer () external view returns (int)',
      'function decimals () external view returns (uint8)',
    ]);

    underlyingOracle = await deployMockContract(owner, [
      'function latestAnswer () external view returns (int)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.decimals.returns(8);
    await underlyingOracle.mock.decimals.returns(8);
    await baseOracle.mock.latestAnswer.returns(parseUnits('1', 8));
    await setUnderlyingPrice(parseUnits(spotPrice.toString(), 8));

    let tx = await manager.deployPool(
      base.address,
      underlying.address,
      baseOracle.address,
      underlyingOracle.address,
      fixedFromFloat(1.22 * 1.22),
    );

    let poolAddress = (await tx.wait()).events![0].args!.pool;
    proxy = ManagedProxyOwnable__factory.connect(poolAddress, owner);
    pool = PoolMock__factory.connect(poolAddress, owner);

    //

    tx = await manager.deployPool(
      base.address,
      underlyingWeth.address,
      baseOracle.address,
      underlyingOracle.address,
      fixedFromFloat(1.1),
    );

    poolAddress = (await tx.wait()).events![0].args!.pool;
    poolWeth = PoolMock__factory.connect(poolAddress, owner);

    //

    underlying = ERC20Mock__factory.connect(
      (await pool.getPoolSettings()).underlying,
      owner,
    );
    poolUtil = new PoolUtil({ pool, underlying, base });
  });

  describeBehaviorOfManagedProxyOwnable({
    deploy: async () => proxy,
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
        await pool.removeUnderwriter(formatAddress(value), true);
        queue = queue.filter((el) => el !== value);
        // console.log(queue);
        expect(await pool.getUnderwriter()).to.eq(
          formatAddress(queue.length ? queue[0] : 0),
        );
      };
      const addAddress = async (value: number) => {
        await pool.addUnderwriter(formatAddress(value), true);

        if (!queue.includes(value)) {
          queue.push(value);
        }

        // console.log(queue);
        expect(await pool.getUnderwriter()).to.eq(formatAddress(queue[0]));
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
      await removeAddress(1);
      await removeAddress(6);
      await removeAddress(9);
      await addAddress(3);
      await addAddress(3);
      await addAddress(9);
      await addAddress(5);

      while (queue.length) {
        // console.log(queue);
        await removeAddress(queue[0]);
      }
    });
  });

  describe('#getUnderlying', function () {
    it('returns underlying address', async () => {
      expect((await pool.getPoolSettings()).underlying).to.eq(
        underlying.address,
      );
    });
  });

  describe('#getBase', function () {
    it('returns base address', async () => {
      expect((await pool.getPoolSettings()).base).to.eq(base.address);
    });
  });

  describe('#quote', function () {
    it('should revert if no liquidity', async () => {
      const maturity = poolUtil.getMaturity(17);
      const strike64x64 = fixedFromFloat(spotPrice * 1.25);
      const spot64x64 = fixedFromFloat(spotPrice);

      await expect(
        pool.quote({
          maturity,
          strike64x64,
          spot64x64,
          amount: parseUnderlying('1'),
          isCall: true,
          emaVarianceAnnualized64x64: await pool.callStatic.update(),
        }),
      ).to.be.revertedWith('no liq');
    });

    describe('call', () => {
      it('should return price for given call option parameters', async () => {
        await poolUtil.depositLiquidity(owner, parseUnderlying('10'), true);

        const strike64x64 = fixedFromFloat(2500);
        const spot64x64 = fixedFromFloat(spotPrice);
        const now = getCurrentTimestamp();

        const q = await pool.quote({
          maturity: now + 10 * 24 * 3600,
          strike64x64,
          spot64x64,
          amount: parseUnderlying('1'),
          isCall: true,
          emaVarianceAnnualized64x64: await pool.callStatic.update(),
        });

        expect(fixedToNumber(q.baseCost64x64) * spotPrice).to.almost(70.92);
        expect(fixedToNumber(q.feeCost64x64)).to.eq(0);
        expect(fixedToNumber(q.cLevel64x64)).to.almost(2.21);
        expect(
          (fixedToNumber(q.baseCost64x64) * spotPrice) /
            fixedToNumber(q.cLevel64x64) /
            fixedToNumber(q.slippageCoefficient64x64),
        ).to.almost(30.51);
      });
    });

    describe('put', () => {
      it('should return price for given put option parameters', async () => {
        await poolUtil.depositLiquidity(owner, parseBase('10000'), false);

        const strike64x64 = fixedFromFloat(1750);
        const spot64x64 = fixedFromFloat(spotPrice);
        const now = getCurrentTimestamp();

        const q = await pool.quote({
          maturity: now + 10 * 24 * 3600,
          strike64x64,
          spot64x64,
          amount: parseUnderlying('1'),
          isCall: false,
          emaVarianceAnnualized64x64: await pool.callStatic.update(),
        });

        expect(fixedToNumber(q.baseCost64x64)).to.almost(114.63);
        expect(fixedToNumber(q.feeCost64x64)).to.eq(0);
        expect(fixedToNumber(q.cLevel64x64)).to.almost(2);
        expect(
          fixedToNumber(q.baseCost64x64) /
            fixedToNumber(q.cLevel64x64) /
            fixedToNumber(q.slippageCoefficient64x64),
        ).to.almost(57.31);
      });
    });
  });

  describe('#deposit', function () {
    describe('call', () => {
      it('should grant sender share tokens with ERC20 deposit (call)', async () => {
        await underlying.mint(owner.address, 100);
        await underlying.approve(pool.address, ethers.constants.MaxUint256);
        await expect(() => pool.deposit('100', true)).to.changeTokenBalance(
          underlying,
          owner,
          -100,
        );
        expect(
          await pool.balanceOf(owner.address, underlyingFreeLiqToken),
        ).to.eq(100);
      });

      it('should grand sender share tokens with WETH deposit', async () => {
        // Use WETH tokens
        await underlyingWeth.deposit({ value: 100 });
        await underlyingWeth.approve(
          poolWeth.address,
          ethers.constants.MaxUint256,
        );
        await expect(() => poolWeth.deposit('50', true)).to.changeTokenBalance(
          underlyingWeth,
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

        expect(await underlyingWeth.balanceOf(owner.address)).to.eq(0);
        expect(
          await poolWeth.balanceOf(owner.address, underlyingFreeLiqToken),
        ).to.eq(350);
      });

      it('should revert if user send ETH with a token deposit', async () => {
        await underlying.mint(owner.address, 100);
        await underlying.approve(pool.address, ethers.constants.MaxUint256);
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
      it('should grant sender share tokens with ERC20 deposit (put)', async () => {
        await base.mint(owner.address, 100);
        await base.approve(pool.address, ethers.constants.MaxUint256);
        await expect(() => pool.deposit('100', false)).to.changeTokenBalance(
          base,
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
          await poolUtil.depositLiquidity(owner, 100, isCall);

          await expect(pool.withdraw('100', isCall)).to.be.revertedWith(
            'liq lock 1d',
          );

          await increaseTimestamp(23 * 3600);
          await expect(pool.withdraw('100', isCall)).to.be.revertedWith(
            'liq lock 1d',
          );
        });

        it('should return underlying tokens withdrawn by sender', async () => {
          await poolUtil.depositLiquidity(owner, 100, isCall);
          expect(await getToken(isCall).balanceOf(owner.address)).to.eq(0);

          await increaseTimestamp(24 * 3600 + 60);
          await pool.withdraw('100', isCall);
          expect(await getToken(isCall).balanceOf(owner.address)).to.eq(100);
          expect(
            await pool.balanceOf(owner.address, getFreeLiqTokenId(isCall)),
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
        it('should revert if using a maturity less than 1 day in the future', async () => {
          await poolUtil.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = getCurrentTimestamp() + 10 * 3600;
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            pool.connect(buyer).purchase({
              maturity,
              strike64x64,
              amount: parseUnderlying('1'),
              maxCost: parseOption('100', isCall),
              isCall,
            }),
          ).to.be.revertedWith('exp < 1 day');
        });

        it('should revert if using a maturity more than 28 days in the future', async () => {
          await poolUtil.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = poolUtil.getMaturity(30);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            pool.connect(buyer).purchase({
              maturity,
              strike64x64,
              amount: parseUnderlying('1'),
              maxCost: parseOption('100', isCall),
              isCall,
            }),
          ).to.be.revertedWith('exp > 28 days');
        });

        it('should revert if using a maturity not corresponding to end of UTC day', async () => {
          await poolUtil.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = poolUtil.getMaturity(10).add(3600);
          const strike64x64 = fixedFromFloat(1.5);

          await expect(
            pool.connect(buyer).purchase({
              maturity,
              strike64x64,
              amount: parseUnderlying('1'),
              maxCost: parseOption('100', isCall),
              isCall,
            }),
          ).to.be.revertedWith('exp not end UTC day');
        });

        it('should revert if using a strike > 2x spot', async () => {
          await poolUtil.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(spotPrice * 2.01);

          await expect(
            pool.connect(buyer).purchase({
              maturity,
              strike64x64,
              amount: parseUnderlying('1'),
              maxCost: parseOption('100', isCall),
              isCall,
            }),
          ).to.be.revertedWith('strike > 2x spot');
        });

        it('should revert if using a strike < 0.5x spot', async () => {
          await poolUtil.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(spotPrice * 0.49);

          await expect(
            pool.connect(buyer).purchase({
              maturity,
              strike64x64,
              amount: parseUnderlying('1'),
              maxCost: parseOption('100', isCall),
              isCall,
            }),
          ).to.be.revertedWith('strike < 0.5x spot');
        });

        it('should revert if cost is above max cost', async () => {
          await poolUtil.depositLiquidity(
            owner,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );
          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await getToken(isCall).mint(
            buyer.address,
            parseOption('100', isCall),
          );
          await getToken(isCall)
            .connect(buyer)
            .approve(pool.address, ethers.constants.MaxUint256);

          await expect(
            pool.connect(buyer).purchase({
              maturity,
              strike64x64,
              amount: parseUnderlying('1'),
              maxCost: parseOption('0.01', isCall),
              isCall,
            }),
          ).to.be.revertedWith('excess slip');
        });

        it('should successfully purchase an option', async () => {
          await poolUtil.depositLiquidity(
            lp1,
            parseOption(isCall ? '100' : '100000', isCall),
            isCall,
          );

          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          const purchaseAmountNb = 10;
          const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

          const quote = await pool.quote({
            maturity,
            strike64x64,
            spot64x64: fixedFromFloat(spotPrice),
            amount: purchaseAmount,
            isCall,
            emaVarianceAnnualized64x64: await pool.callStatic.update(),
          });

          const mintAmount = parseOption('1000', isCall);
          await getToken(isCall).mint(buyer.address, mintAmount);
          await getToken(isCall)
            .connect(buyer)
            .approve(pool.address, ethers.constants.MaxUint256);

          await pool.connect(buyer).purchase({
            maturity,
            strike64x64,
            amount: purchaseAmount,
            maxCost: getMaxCost(
              quote.baseCost64x64,
              quote.feeCost64x64,
              isCall,
            ),
            isCall,
          });

          const newBalance = await getToken(isCall).balanceOf(buyer.address);

          expect(bnToNumber(newBalance, getTokenDecimals(isCall))).to.almost(
            bnToNumber(mintAmount, getTokenDecimals(isCall)) -
              fixedToNumber(quote.baseCost64x64),
          );

          const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

          if (isCall) {
            expect(
              bnToNumber(
                await pool.balanceOf(lp1.address, getFreeLiqTokenId(isCall)),
                DECIMALS_UNDERLYING,
              ),
            ).to.almost(
              100 - purchaseAmountNb + fixedToNumber(quote.baseCost64x64),
            );
          } else {
            expect(
              bnToNumber(
                await pool.balanceOf(lp1.address, getFreeLiqTokenId(isCall)),
                DECIMALS_BASE,
              ),
            ).to.almost(
              100000 -
                purchaseAmountNb * getStrike(isCall) +
                fixedToNumber(quote.baseCost64x64),
            );
          }

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

            await poolUtil.depositLiquidity(signer, depositAmount, isCall);
            amountInPool = amountInPool.add(depositAmount);
          }

          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          // 10 intervals used
          const purchaseAmountNb = 10;
          const purchaseAmount = parseUnderlying(purchaseAmountNb.toString());

          const quote = await pool.quote({
            maturity,
            strike64x64,
            spot64x64: fixedFromFloat(spotPrice),
            amount: purchaseAmount,
            isCall,
            emaVarianceAnnualized64x64: await pool.callStatic.update(),
          });

          await getToken(isCall).mint(
            buyer.address,
            parseOption('1000', isCall),
          );
          await getToken(isCall)
            .connect(buyer)
            .approve(pool.address, ethers.constants.MaxUint256);

          const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

          const tx = await pool.connect(buyer).purchase({
            maturity,
            strike64x64,
            amount: purchaseAmount,
            maxCost: getMaxCost(
              quote.baseCost64x64,
              quote.feeCost64x64,
              isCall,
            ),
            isCall,
          });

          expect(await pool.balanceOf(buyer.address, tokenId.long)).to.eq(
            purchaseAmount,
          );

          let amount = purchaseAmountNb;

          let i = 0;
          for (const s of signers) {
            if (s.address === buyer.address) continue;

            let expectedAmount = 0;

            if (isCall) {
              if (i < purchaseAmountNb) {
                if (i < purchaseAmountNb - 1) {
                  // For all underwriter before last intervals, we add premium which is automatically reinvested
                  expectedAmount =
                    1 + fixedToNumber(quote.baseCost64x64) / purchaseAmountNb;
                } else {
                  // For underwriter of the last interval, we subtract baseCost,
                  // as previous intervals were > 1 because of reinvested premium
                  expectedAmount = 1 - fixedToNumber(quote.baseCost64x64);
                }
              }
            } else {
              const totalToPay = purchaseAmountNb * getStrike(isCall);
              const intervalAmount =
                (depositAmountNb *
                  (totalToPay + fixedToNumber(quote.baseCost64x64))) /
                totalToPay /
                getStrike(isCall);

              if (intervalAmount < amount) {
                expectedAmount = intervalAmount;
                amount -= intervalAmount;
              } else {
                expectedAmount = amount;
                amount = 0;
              }
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
          console.log('GAS', r.gasUsed.toString());
        });
      });
    }
  });

  describe('#exerciseFrom', function () {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should revert if token is a SHORT token', async () => {
          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await poolUtil.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
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
          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await poolUtil.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            pool
              .connect(buyer)
              .exerciseFrom(buyer.address, longTokenId, parseUnderlying('1')),
          ).to.be.revertedWith('not ITM');
        });

        it('should successfully exercise', async () => {
          const maturity = poolUtil.getMaturity(10);
          const strike = getStrike(isCall);
          const strike64x64 = fixedFromFloat(strike);
          const amountNb = 10;
          const amount = parseUnderlying(amountNb.toString());
          const initialFreeLiqAmount = isCall
            ? amount
            : parseBase(formatUnderlying(amount)).mul(
                fixedToNumber(strike64x64),
              );

          const quote = await poolUtil.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          const price = isCall ? strike * 1.4 : strike * 0.7;
          await setUnderlyingPrice(parseUnits(price.toString(), 8));

          const curBalance = await getToken(isCall).balanceOf(buyer.address);

          await pool
            .connect(buyer)
            .exerciseFrom(buyer.address, longTokenId, amount);

          const exerciseValue = getExerciseValue(
            price,
            strike,
            amountNb,
            isCall,
          );
          const premium = (await getToken(isCall).balanceOf(buyer.address)).sub(
            curBalance,
          );

          expect(Number(formatOption(premium, isCall))).to.almost(
            exerciseValue,
          );
          expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(0);

          const freeLiqAfter = await pool.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );

          // Free liq = initial amount + premia paid
          expect(
            Number(formatOption(initialFreeLiqAmount, isCall)) +
              fixedToNumber(quote.baseCost64x64) -
              exerciseValue,
          ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
        });

        it('should revert when exercising on behalf of user not approved', async () => {
          const maturity = poolUtil.getMaturity(10);
          const strike = getStrike(isCall);
          const strike64x64 = fixedFromFloat(strike);
          const amountNb = 10;
          const amount = parseUnderlying(amountNb.toString());

          await poolUtil.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
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
          const maturity = poolUtil.getMaturity(10);
          const strike = getStrike(isCall);
          const strike64x64 = fixedFromFloat(strike);
          const amountNb = 10;
          const amount = parseUnderlying(amountNb.toString());
          const initialFreeLiqAmount = isCall
            ? amount
            : parseBase(formatUnderlying(amount)).mul(
                fixedToNumber(strike64x64),
              );

          const quote = await poolUtil.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          const price = isCall ? strike * 1.4 : strike * 0.7;
          await setUnderlyingPrice(parseUnits(price.toString(), 8));

          const curBalance = await getToken(isCall).balanceOf(buyer.address);

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
          const premium = (await getToken(isCall).balanceOf(buyer.address)).sub(
            curBalance,
          );
          expect(Number(formatOption(premium, isCall))).to.almost(
            exerciseValue,
          );

          expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(0);

          const freeLiqAfter = await pool.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );

          // Free liq = initial amount + premia paid
          expect(
            Number(formatOption(initialFreeLiqAmount, isCall)) +
              fixedToNumber(quote.baseCost64x64) -
              exerciseValue,
          ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
        });
      });
    }
  });

  describe('#processExpired', function () {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should revert if option is not expired', async () => {
          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await poolUtil.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
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
          const maturity = poolUtil.getMaturity(20);
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

          const quote = await poolUtil.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          await setTimestamp(maturity.add(100).toNumber());

          const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

          const price = isCall ? strike * 0.7 : strike * 1.4;
          await setUnderlyingPrice(parseUnits(price.toString(), 8));

          // Free liq = premia paid after purchase
          expect(
            Number(
              formatOption(
                await pool.balanceOf(lp1.address, getFreeLiqTokenId(isCall)),
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
                await getToken(isCall).balanceOf(buyer.address),
                isCall,
              ),
            ),
          ).to.almost(
            Number(formatOption(initialBuyerAmount, isCall)) -
              fixedToNumber(quote.baseCost64x64),
          );

          const freeLiqAfter = await pool.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );

          // Free liq = initial amount + premia paid
          expect(
            Number(formatOption(initialFreeLiqAmount, isCall)) +
              fixedToNumber(quote.baseCost64x64),
          ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
        });

        it('should successfully process expired option ITM', async () => {
          const maturity = poolUtil.getMaturity(20);
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

          const quote = await poolUtil.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          await setTimestamp(maturity.add(100).toNumber());

          const tokenId = getOptionTokenIds(maturity, strike64x64, isCall);

          const price = isCall ? strike * 1.4 : strike * 0.7;
          await setUnderlyingPrice(parseUnits(price.toString(), 8));

          // Free liq = premia paid after purchase
          expect(
            Number(
              formatOption(
                await pool.balanceOf(lp1.address, getFreeLiqTokenId(isCall)),
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
                await getToken(isCall).balanceOf(buyer.address),
                isCall,
              ),
            ),
          ).to.almost(
            Number(formatOption(initialBuyerAmount, isCall)) -
              fixedToNumber(quote.baseCost64x64) +
              exerciseValue,
          );

          const freeLiqAfter = await pool.balanceOf(
            lp1.address,
            getFreeLiqTokenId(isCall),
          );

          // Free liq = initial amount + premia paid - exerciseValue
          expect(
            Number(formatOption(initialFreeLiqAmount, isCall)) +
              fixedToNumber(quote.baseCost64x64) -
              exerciseValue,
          ).to.almost(Number(formatOption(freeLiqAfter, isCall)));
        });
      });
    }
  });

  describe('#reassign', function () {
    for (const isCall of [true, false]) {
      describe(isCall ? 'call' : 'put', () => {
        it('should revert if token is a LONG token', async () => {
          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await poolUtil.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          await poolUtil.depositLiquidity(
            lp2,
            parseOption('2', isCall),
            isCall,
          );

          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

          await expect(
            pool.connect(lp1).reassign(longTokenId, parseUnderlying('1')),
          ).to.be.revertedWith('invalid type');
        });

        it('should revert if option is expired', async () => {
          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));

          await poolUtil.purchaseOption(
            lp1,
            buyer,
            parseUnderlying('1'),
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
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
          const maturity = poolUtil.getMaturity(10);
          const strike64x64 = fixedFromFloat(getStrike(isCall));
          const amount = parseUnderlying('1');

          await poolUtil.purchaseOption(
            lp1,
            buyer,
            amount,
            maturity,
            fixedFromFloat(spotPrice),
            strike64x64,
            isCall,
          );

          await poolUtil.depositLiquidity(
            lp2,
            isCall
              ? parseUnderlying('1').mul(2)
              : parseBase('1').mul(fixedToNumber(strike64x64)).mul(2),
            isCall,
          );

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });

          const shortTokenBalance = await pool.balanceOf(
            lp1.address,
            shortTokenId,
          );

          await pool.connect(lp1).reassign(shortTokenId, shortTokenBalance);

          expect(await pool.balanceOf(lp1.address, shortTokenId)).to.eq(0);
          expect(await pool.balanceOf(lp2.address, shortTokenId)).to.eq(
            shortTokenBalance,
          );
        });
      });
    }
  });
});
