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
import { parseEther } from 'ethers/lib/utils';
import { PoolUtil, TokenType } from './PoolUtil';
import { fixedFromFloat, fixedToNumber, getTokenIdFor } from '../utils/math';
import chaiAlmost from 'chai-almost';
import { BigNumber } from 'ethers';
import { describeBehaviorOfPoolProxyPurchase } from './PoolProxy.behavior';

chai.use(chaiAlmost(0.01));

const SYMBOL_BASE = 'SYMBOL_BASE';
const SYMBOL_UNDERLYING = 'SYMBOL_UNDERLYING';

describe('PoolProxy', function () {
  let owner: SignerWithAddress;
  let lp: SignerWithAddress;
  let buyer: SignerWithAddress;

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

  const underlyingFreeLiqToken = getTokenIdFor({
    tokenType: TokenType.UnderlyingFreeLiq,
    maturity: BigNumber.from(0),
    strike64x64: BigNumber.from(0),
  });
  const baseFreeLiqToken = getTokenIdFor({
    tokenType: TokenType.BaseFreeLiq,
    maturity: BigNumber.from(0),
    strike64x64: BigNumber.from(0),
  });

  const spotPrice = 2500;

  const setUnderlyingPrice = async (price: BigNumber) => {
    await underlyingOracle.mock.latestRoundData.returns(1, price, 1, 5, 1);
  };

  beforeEach(async function () {
    await resetHardhat();
    [owner, lp, buyer] = await ethers.getSigners();

    //

    const erc20Factory = new ERC20Mock__factory(owner);

    base = await erc20Factory.deploy(SYMBOL_BASE);
    await base.deployed();
    underlying = await erc20Factory.deploy(SYMBOL_UNDERLYING);
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
      'function latestRoundData () external view returns (uint80, int, uint, uint, uint80)',
      'function decimals () external view returns (uint8)',
    ]);

    underlyingOracle = await deployMockContract(owner, [
      'function latestRoundData () external view returns (uint80, int, uint, uint, uint80)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.decimals.returns(8);
    await underlyingOracle.mock.decimals.returns(8);
    await baseOracle.mock.latestRoundData.returns(1, parseEther('1'), 1, 5, 1);
    await setUnderlyingPrice(parseEther(spotPrice.toString()));

    let tx = await manager.deployPool(
      base.address,
      underlying.address,
      baseOracle.address,
      underlyingOracle.address,
      fixedFromFloat(spotPrice * 0.999),
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
      fixedFromFloat(spotPrice * 0.999),
      fixedFromFloat(0.1),
      fixedFromFloat(1.1),
    );

    poolAddress = (await tx.wait()).events![0].args!.pool;
    poolWeth = PoolMock__factory.connect(poolAddress, owner);

    //

    underlying = ERC20Mock__factory.connect(await pool.getUnderlying(), owner);
    poolUtil = new PoolUtil({ pool, underlying, base });
  });

  describeBehaviorOfManagedProxyOwnable({
    deploy: async () => proxy,
    implementationFunction: 'getBase()',
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
      expect(await pool.getUnderlying()).to.eq(underlying.address);
    });
  });

  describe('#getBase', function () {
    it('returns base address', async () => {
      expect(await pool.getBase()).to.eq(base.address);
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
          amount: parseEther('1'),
          isCall: true,
        }),
      ).to.be.revertedWith('Pool: No liq');
    });

    describe('call', () => {
      it('should return price for given call option parameters', async () => {
        await poolUtil.depositLiquidity(owner, parseEther('10'), true);

        const maturity = poolUtil.getMaturity(17);
        const strike64x64 = fixedFromFloat(spotPrice * 1.25);
        const spot64x64 = fixedFromFloat(spotPrice);

        const quote = await pool.quote({
          maturity,
          strike64x64,
          spot64x64,
          amount: parseEther('1'),
          isCall: true,
        });

        expect(fixedToNumber(quote.baseCost64x64)).to.almost(0.0488);
        expect(fixedToNumber(quote.feeCost64x64)).to.eq(0);
        expect(fixedToNumber(quote.cLevel64x64)).to.almost(2.21);
      });
    });

    describe('put', () => {
      it('should return price for given put option parameters', async () => {
        await poolUtil.depositLiquidity(owner, parseEther('10'), false);

        const maturity = poolUtil.getMaturity(17);
        const strike64x64 = fixedFromFloat(spotPrice * 0.75);
        const spot64x64 = fixedFromFloat(spotPrice);

        const quote = await pool.quote({
          maturity,
          strike64x64,
          spot64x64,
          amount: parseEther('1'),
          isCall: false,
        });

        expect(fixedToNumber(quote.baseCost64x64)).to.almost(50.29);
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
        ).to.be.revertedWith('Pool: not WETH deposit');
      });

      it('should revert if user send too much ETH with a WETH deposit', async () => {
        await expect(
          poolWeth.deposit('200', true, { value: 201 }),
        ).to.be.revertedWith('Pool: too much ETH sent');
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
          'Pool: liq must be locked 1 day',
        );

        await setTimestamp(getCurrentTimestamp() + 23 * 3600);
        await expect(pool.withdraw('100', true)).to.be.revertedWith(
          'Pool: liq must be locked 1 day',
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
          'Pool: liq must be locked 1 day',
        );

        await setTimestamp(getCurrentTimestamp() + 23 * 3600);
        await expect(pool.withdraw('100', false)).to.be.revertedWith(
          'Pool: liq must be locked 1 day',
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
    describeBehaviorOfPoolProxyPurchase({
      pool: () => pool,
      poolUtil: () => poolUtil,
      owner: () => owner,
      buyer: () => buyer,
      lp: () => lp,
      spotPrice,
      underlying: () => underlying,
      base: () => base,
      isCall: true,
    });

    describeBehaviorOfPoolProxyPurchase({
      pool: () => pool,
      poolUtil: () => poolUtil,
      owner: () => owner,
      buyer: () => buyer,
      lp: () => lp,
      spotPrice,
      underlying: () => underlying,
      base: () => base,
      isCall: false,
    });
  });

  describe('#exercise', function () {
    it('should revert if token is a SHORT_CALL', async () => {
      const maturity = poolUtil.getMaturity(10);
      const strike64x64 = fixedFromFloat(spotPrice * 1.25);

      await poolUtil.purchaseOption(
        lp,
        buyer,
        parseEther('1'),
        maturity,
        strike64x64,
        true,
      );

      const shortTokenId = getTokenIdFor({
        tokenType: TokenType.ShortCall,
        maturity,
        strike64x64,
      });

      await expect(
        pool.connect(lp).exercise({
          longTokenId: shortTokenId,
          amount: parseEther('1'),
          isCall: true,
        }),
      ).to.be.revertedWith('Pool: invalid token type');
    });

    it('should revert if option is not ITM', async () => {
      const maturity = poolUtil.getMaturity(10);
      const strike64x64 = fixedFromFloat(spotPrice * 1.25);

      await poolUtil.purchaseOption(
        lp,
        buyer,
        parseEther('1'),
        maturity,
        strike64x64,
        true,
      );

      const longTokenId = getTokenIdFor({
        tokenType: TokenType.LongCall,
        maturity,
        strike64x64,
      });

      await expect(
        pool
          .connect(buyer)
          .exercise({ longTokenId, amount: parseEther('1'), isCall: true }),
      ).to.be.revertedWith('Pool: not ITM');
    });

    it('should successfully exercise', async () => {
      const maturity = poolUtil.getMaturity(10);
      const strike64x64 = fixedFromFloat(spotPrice * 1.25);

      await poolUtil.purchaseOption(
        lp,
        buyer,
        parseEther('1'),
        maturity,
        strike64x64,
        true,
      );

      const longTokenId = getTokenIdFor({
        tokenType: TokenType.LongCall,
        maturity,
        strike64x64,
      });

      await setUnderlyingPrice(parseEther((spotPrice * 1.3).toString()));
      await pool
        .connect(buyer)
        .exercise({ longTokenId, amount: parseEther('1'), isCall: true });

      // ToDo : Finish to write test
    });
  });
});
