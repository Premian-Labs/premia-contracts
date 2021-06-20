import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  ManagedProxyOwnable,
  ManagedProxyOwnable__factory,
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
import { resetHardhat, setTimestamp } from '../evm';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { parseUnits } from 'ethers/lib/utils';
import {
  formatBase,
  formatUnderlying,
  getTokenDecimals,
  parseBase,
  parseOption,
  parseUnderlying,
  PoolUtil,
  TokenType,
} from './PoolUtil';
import {
  bnToNumber,
  fixedFromFloat,
  fixedToNumber,
  formatTokenId,
} from '../utils/math';
import chaiAlmost from 'chai-almost';
import { BigNumber } from 'ethers';

chai.use(chaiAlmost(0.01));

const SYMBOL_BASE = 'SYMBOL_BASE';
const SYMBOL_UNDERLYING = 'SYMBOL_UNDERLYING';
export const DECIMALS_BASE = 18;
export const DECIMALS_UNDERLYING = 8;

describe('PoolProxy', function () {
  let owner: SignerWithAddress;
  let lp1: SignerWithAddress;
  let lp2: SignerWithAddress;
  let buyer: SignerWithAddress;
  let thirdParty: SignerWithAddress;

  let premia: Premia;
  let proxy: ManagedProxyOwnable;
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
          1.02
        ).toString(),
      );
    } else {
      return parseBase(
        (
          (fixedToNumber(baseCost64x64) + fixedToNumber(feeCost64x64)) *
          1.02
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

  const spotPrice = 2500;

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

    const poolImp = await new PoolMock__factory(owner).deploy(
      underlyingWeth.address,
    );

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
      fixedFromFloat(0.1),
      fixedFromFloat(1.1),
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
      fixedFromFloat(0.1),
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
        }),
      ).to.be.revertedWith('no liq');
    });

    describe('call', () => {
      it('should return price for given call option parameters', async () => {
        await poolUtil.depositLiquidity(owner, parseUnderlying('10'), true);

        const maturity = poolUtil.getMaturity(17);
        const strike64x64 = fixedFromFloat(spotPrice * 1.25);
        const spot64x64 = fixedFromFloat(spotPrice);

        const quote = await pool.quote({
          maturity,
          strike64x64,
          spot64x64,
          amount: parseUnderlying('1'),
          isCall: true,
        });

        expect(fixedToNumber(quote.baseCost64x64)).to.almost(0.0488);
        expect(fixedToNumber(quote.feeCost64x64)).to.eq(0);
        expect(fixedToNumber(quote.cLevel64x64)).to.almost(2.21);
      });
    });

    describe('put', () => {
      it('should return price for given put option parameters', async () => {
        await poolUtil.depositLiquidity(owner, parseBase('10'), false);

        const maturity = poolUtil.getMaturity(17);
        const strike64x64 = fixedFromFloat(spotPrice * 0.75);
        const spot64x64 = fixedFromFloat(spotPrice);

        const quote = await pool.quote({
          maturity,
          strike64x64,
          spot64x64,
          amount: parseUnderlying('1'),
          isCall: false,
        });

        const baseCost = fixedToNumber(quote.baseCost64x64);
        // Setting a small range, as baseCost will fluctuate a bit based on current time
        console.log(baseCost);
        expect(49 < baseCost && baseCost < 55).to.be.true;
        expect(fixedToNumber(quote.feeCost64x64)).to.eq(0);
        expect(fixedToNumber(quote.cLevel64x64)).to.almost(2.21);
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
    describe('call', () => {
      it('should fail withdrawing if < 1 day after deposit', async () => {
        await poolUtil.depositLiquidity(owner, 100, true);

        await expect(pool.withdraw('100', true)).to.be.revertedWith(
          'liq lock 1d',
        );

        await setTimestamp(getCurrentTimestamp() + 23 * 3600);
        await expect(pool.withdraw('100', true)).to.be.revertedWith(
          'liq lock 1d',
        );
      });

      it('should return underlying tokens withdrawn by sender', async () => {
        await poolUtil.depositLiquidity(owner, 100, true);
        expect(await underlying.balanceOf(owner.address)).to.eq(0);

        await setTimestamp(getCurrentTimestamp() + 24 * 3600 + 60);
        await pool.withdraw('100', true);
        expect(await underlying.balanceOf(owner.address)).to.eq(100);
        expect(
          await pool.balanceOf(owner.address, underlyingFreeLiqToken),
        ).to.eq(0);
      });
    });

    describe('put', () => {
      it('should fail withdrawing if < 1 day after deposit', async () => {
        await poolUtil.depositLiquidity(owner, 100, false);

        await expect(pool.withdraw('100', false)).to.be.revertedWith(
          'liq lock 1d',
        );

        await setTimestamp(getCurrentTimestamp() + 23 * 3600);
        await expect(pool.withdraw('100', false)).to.be.revertedWith(
          'liq lock 1d',
        );
      });

      it('should return underlying tokens withdrawn by sender', async () => {
        await poolUtil.depositLiquidity(owner, 100, false);
        expect(await base.balanceOf(owner.address)).to.eq(0);

        await setTimestamp(getCurrentTimestamp() + 24 * 3600 + 60);
        await pool.withdraw('100', false);
        expect(await base.balanceOf(owner.address)).to.eq(100);
        expect(
          await pool.balanceOf(owner.address, underlyingFreeLiqToken),
        ).to.eq(0);
      });
    });
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

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });
          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

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

          expect(await pool.balanceOf(lp1.address, longTokenId)).to.eq(0);
          expect(await pool.balanceOf(lp1.address, shortTokenId)).to.eq(
            purchaseAmount,
          );

          expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(
            purchaseAmount,
          );
          expect(await pool.balanceOf(buyer.address, shortTokenId)).to.eq(0);
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
          });

          await getToken(isCall).mint(
            buyer.address,
            parseOption('1000', isCall),
          );
          await getToken(isCall)
            .connect(buyer)
            .approve(pool.address, ethers.constants.MaxUint256);

          const shortTokenId = formatTokenId({
            tokenType: getShort(isCall),
            maturity,
            strike64x64,
          });
          const longTokenId = formatTokenId({
            tokenType: getLong(isCall),
            maturity,
            strike64x64,
          });

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

          expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(
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
                await pool.balanceOf(s.address, shortTokenId),
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

          await poolUtil.purchaseOption(
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
          await setUnderlyingPrice(parseUnits(price.toString(), 8));

          const underlyingBalance = await underlying.balanceOf(buyer.address);
          const baseBalance = await base.balanceOf(buyer.address);

          await pool
            .connect(buyer)
            .exerciseFrom(buyer.address, longTokenId, amount);

          if (isCall) {
            const expectedReturn = ((price - strike) * amountNb) / price;
            const premium = (await underlying.balanceOf(buyer.address)).sub(
              underlyingBalance,
            );

            expect(Number(formatUnderlying(premium))).to.almost(expectedReturn);
          } else {
            const expectedReturn = (strike - price) * amountNb;
            const premium = (await base.balanceOf(buyer.address)).sub(
              baseBalance,
            );

            expect(Number(formatBase(premium))).to.eq(expectedReturn);
          }

          expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(0);
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

          await poolUtil.purchaseOption(
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
          await setUnderlyingPrice(parseUnits(price.toString(), 8));

          const underlyingBalance = await underlying.balanceOf(buyer.address);
          const baseBalance = await base.balanceOf(buyer.address);

          await pool.connect(buyer).setApprovalForAll(thirdParty.address, true);

          await pool
            .connect(thirdParty)
            .exerciseFrom(buyer.address, longTokenId, amount);

          if (isCall) {
            const expectedReturn = ((price - strike) * amountNb) / price;
            const premium = (await underlying.balanceOf(buyer.address)).sub(
              underlyingBalance,
            );

            expect(Number(formatUnderlying(premium))).to.almost(expectedReturn);
          } else {
            const expectedReturn = (strike - price) * amountNb;
            const premium = (await base.balanceOf(buyer.address)).sub(
              baseBalance,
            );

            expect(Number(formatBase(premium))).to.eq(expectedReturn);
          }

          expect(await pool.balanceOf(buyer.address, longTokenId)).to.eq(0);
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

          console.log(shortTokenBalance.toString());

          await setTimestamp(getCurrentTimestamp() + 11 * 24 * 3600);

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
