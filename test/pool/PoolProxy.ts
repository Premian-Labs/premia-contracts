import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  ManagedProxyOwnable,
  ManagedProxyOwnable__factory,
  Premia,
  Premia__factory,
  PoolMock,
  PoolMock__factory,
  ProxyManager__factory,
  WETH9__factory,
  WETH9,
} from '../../typechain';

import { describeBehaviorOfManagedProxyOwnable } from '@solidstate/spec';
import { describeBehaviorOfPool } from './Pool.behavior';
import { BigNumber } from 'ethers';
import { expect } from 'chai';
import { resetHardhat, setTimestamp } from '../evm';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import { deployMockContract } from 'ethereum-waffle';
import { parseEther } from 'ethers/lib/utils';
import { PoolUtil } from './PoolUtil';

const SYMBOL_BASE = 'SYMBOL_BASE';
const SYMBOL_UNDERLYING = 'SYMBOL_UNDERLYING';

const fixedFromBigNumber = function (bn: BigNumber) {
  return bn.abs().shl(64).mul(bn.abs().div(bn));
};

const fixedFromFloat = function (float: number) {
  const [integer = '', decimal = ''] = float.toString().split('.');
  return fixedFromBigNumber(ethers.BigNumber.from(`${integer}${decimal}`)).div(
    ethers.BigNumber.from(`1${'0'.repeat(decimal.length)}`),
  );
};

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
  const freeLiquidityTokenId = 0;

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

    const oracle0 = await deployMockContract(owner, [
      'function latestRoundData () external view returns (uint80, int, uint, uint, uint80)',
      'function decimals () external view returns (uint8)',
    ]);

    const oracle1 = await deployMockContract(owner, [
      'function latestRoundData () external view returns (uint80, int, uint, uint, uint80)',
      'function decimals () external view returns (uint8)',
    ]);

    await oracle0.mock.decimals.returns(8);
    await oracle1.mock.decimals.returns(8);
    await oracle0.mock.latestRoundData.returns(1, parseEther('10'), 1, 5, 1);
    await oracle1.mock.latestRoundData.returns(1, parseEther('1'), 1, 5, 1);

    let tx = await manager.deployPool(
      base.address,
      underlying.address,
      oracle0.address,
      oracle1.address,
    );

    let poolAddress = (await tx.wait()).events![0].args!.pool;
    proxy = ManagedProxyOwnable__factory.connect(poolAddress, owner);
    pool = PoolMock__factory.connect(poolAddress, owner);

    //

    tx = await manager.deployPool(
      base.address,
      underlyingWeth.address,
      oracle0.address,
      oracle1.address,
    );

    poolAddress = (await tx.wait()).events![0].args!.pool;
    poolWeth = PoolMock__factory.connect(poolAddress, owner);

    //

    underlying = ERC20Mock__factory.connect(await pool.getUnderlying(), owner);
    poolUtil = new PoolUtil({ pool });
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

  describe('#quote', function () {
    it('returns price for given option parameters');
  });

  describe('#deposit', function () {
    it('returns share tokens granted to sender with ERC20 deposit', async () => {
      await underlying.mint(owner.address, 100);
      await underlying.approve(pool.address, ethers.constants.MaxUint256);
      await expect(() => pool.deposit('100')).to.changeTokenBalance(
        underlying,
        owner,
        -100,
      );
      expect(await pool.balanceOf(owner.address, freeLiquidityTokenId)).to.eq(
        100,
      );
    });

    it('returns share tokens granted to sender with WETH deposit', async () => {
      // Use WETH tokens
      await underlyingWeth.deposit({ value: 100 });
      await underlyingWeth.approve(
        poolWeth.address,
        ethers.constants.MaxUint256,
      );
      await expect(() => poolWeth.deposit('50')).to.changeTokenBalance(
        underlyingWeth,
        owner,
        -50,
      );

      // Use ETH
      await expect(() =>
        poolWeth.deposit('200', { value: 200 }),
      ).to.changeEtherBalance(owner, -200);

      // Use both ETH and WETH tokens
      await expect(() =>
        poolWeth.deposit('100', { value: 50 }),
      ).to.changeEtherBalance(owner, -50);

      expect(await underlyingWeth.balanceOf(owner.address)).to.eq(0);
      expect(
        await poolWeth.balanceOf(owner.address, freeLiquidityTokenId),
      ).to.eq(350);
    });

    it('should revert if user send ETH with a token deposit', async () => {
      await underlying.mint(owner.address, 100);
      await underlying.approve(pool.address, ethers.constants.MaxUint256);
      await expect(pool.deposit('100', { value: 1 })).to.be.revertedWith(
        'Pool: not WETH deposit',
      );
    });

    it('should revert if user send too much ETH with a WETH deposit', async () => {
      await expect(poolWeth.deposit('200', { value: 201 })).to.be.revertedWith(
        'Pool: too much ETH sent',
      );
    });
  });

  describe('#withdraw', function () {
    it('should fail withdrawing if < 1 day after deposit', async () => {
      await poolUtil.depositLiquidity(owner, underlying, 100);

      await expect(pool.withdraw('100')).to.be.revertedWith(
        'Pool: liq must be locked 1 day',
      );

      await setTimestamp(getCurrentTimestamp() + 23 * 3600);
      await expect(pool.withdraw('100')).to.be.revertedWith(
        'Pool: liq must be locked 1 day',
      );
    });

    it('should return underlying tokens withdrawn by sender', async () => {
      await poolUtil.depositLiquidity(owner, underlying, 100);
      expect(await underlying.balanceOf(owner.address)).to.eq(0);

      await setTimestamp(getCurrentTimestamp() + 24 * 3600 + 60);
      await pool.withdraw('100');
      expect(await underlying.balanceOf(owner.address)).to.eq(100);
      expect(await pool.balanceOf(owner.address, freeLiquidityTokenId)).to.eq(
        0,
      );
    });

    it('todo');
  });

  describe('#purchase', function () {
    it('should revert if using a maturity less than 1 day in the future', async () => {
      await poolUtil.depositLiquidity(owner, underlying, parseEther('100'));
      const maturity = getCurrentTimestamp() + 10 * 3600;
      const strikePrice = fixedFromFloat(1.5);

      await expect(
        pool
          .connect(buyer)
          .purchase(maturity, strikePrice, parseEther('1'), parseEther('100')),
      ).to.be.revertedWith('Pool: maturity < 1 day');
    });

    it('should revert if using a maturity more than 28 days in the future', async () => {
      await poolUtil.depositLiquidity(owner, underlying, parseEther('100'));
      const maturity = poolUtil.getMaturity(30);
      const strikePrice = fixedFromFloat(1.5);

      await expect(
        pool
          .connect(buyer)
          .purchase(maturity, strikePrice, parseEther('1'), parseEther('100')),
      ).to.be.revertedWith('Pool: maturity > 28 days');
    });

    it('should revert if using a maturity not corresponding to end of UTC day', async () => {
      await poolUtil.depositLiquidity(owner, underlying, parseEther('100'));
      const maturity = poolUtil.getMaturity(10).add(3600);
      const strikePrice = fixedFromFloat(1.5);

      await expect(
        pool
          .connect(buyer)
          .purchase(maturity, strikePrice, parseEther('1'), parseEther('100')),
      ).to.be.revertedWith('Pool: maturity not end UTC day');
    });

    it('should revert if using a strike > 2x spot', async () => {
      await poolUtil.depositLiquidity(owner, underlying, parseEther('100'));
      const maturity = poolUtil.getMaturity(10);
      const strikePrice = fixedFromFloat(21);

      await expect(
        pool
          .connect(buyer)
          .purchase(maturity, strikePrice, parseEther('1'), parseEther('100')),
      ).to.be.revertedWith(
        'Pool: strike price must not exceed two times spot price',
      );
    });

    it('should revert if using a strike < 0.5x spot', async () => {
      await poolUtil.depositLiquidity(owner, underlying, parseEther('100'));
      const maturity = poolUtil.getMaturity(10);
      const strikePrice = fixedFromFloat(4);

      await expect(
        pool
          .connect(buyer)
          .purchase(maturity, strikePrice, parseEther('1'), parseEther('100')),
      ).to.be.revertedWith(
        'Pool: strike price must be at least one half spot price',
      );
    });

    it('should revert if cost is above max cost', async () => {
      await poolUtil.depositLiquidity(owner, underlying, parseEther('100'));
      const maturity = poolUtil.getMaturity(10);
      const strikePrice = fixedFromFloat(12);

      await underlying.mint(buyer.address, parseEther('100'));
      await underlying
        .connect(buyer)
        .approve(pool.address, ethers.constants.MaxUint256);

      // ToDo : Fix test which fails because of division by 0 in bsPrice when getting quote
      await expect(
        pool
          .connect(buyer)
          .purchase(maturity, strikePrice, parseEther('1'), parseEther('5')),
      ).to.be.revertedWith(
        'Pool: strike price must be at least one half spot price',
      );
    });

    it('should successfully purchase an option', async () => {});
  });

  describe('#exercise', function () {
    describe('(uint256,uint192,uint64)', function () {
      it('todo');
    });

    describe('(uint256,uint256)', function () {
      it('todo');
    });
  });
});
