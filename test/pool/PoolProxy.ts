import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  ManagedProxyOwnable,
  ManagedProxyOwnable__factory,
  Median,
  Median__factory,
  Pair,
  Pair__factory,
  Pool__factory,
  PoolMock,
  PoolMock__factory,
  ProxyManager__factory,
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

  let median: Median;
  let proxy: ManagedProxyOwnable;
  let pool: PoolMock;
  let pair: Pair;
  let asset0: ERC20Mock;
  let asset1: ERC20Mock;
  let underlying: ERC20Mock;
  let poolUtil: PoolUtil;

  beforeEach(async function () {
    await resetHardhat();
    [owner, lp, buyer] = await ethers.getSigners();

    //

    const pairImpl = await new Pair__factory(owner).deploy();
    const poolImp = await new PoolMock__factory(owner).deploy();

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

    median = await new Median__factory(owner).deploy(
      pairImpl.address,
      poolImp.address,
    );

    await median.diamondCut(facetCuts, ethers.constants.AddressZero, '0x');

    //

    const manager = ProxyManager__factory.connect(median.address, owner);

    const erc20Factory = new ERC20Mock__factory(owner);

    const token0 = await erc20Factory.deploy(SYMBOL_BASE);
    await token0.deployed();
    const token1 = await erc20Factory.deploy(SYMBOL_UNDERLYING);
    await token1.deployed();

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

    const tx = await manager.deployPair(
      token0.address,
      token1.address,
      oracle0.address,
      oracle1.address,
    );

    const pairAddress = (await tx.wait()).events![0].args!.pair;
    pair = Pair__factory.connect(pairAddress, owner);
    asset0 = ERC20Mock__factory.connect(await pair.asset0(), owner);
    asset1 = ERC20Mock__factory.connect(await pair.asset1(), owner);
    const pools = await pair.callStatic.getPools();

    proxy = ManagedProxyOwnable__factory.connect(pools[0], owner);
    pool = PoolMock__factory.connect(pools[0], owner);
    underlying = ERC20Mock__factory.connect(await pool.getUnderlying(), owner);
    poolUtil = new PoolUtil({ pool });
  });

  describeBehaviorOfManagedProxyOwnable({
    deploy: async () => proxy,
    implementationFunction: 'getPair()',
    implementationFunctionArgs: [],
  });

  describeBehaviorOfPool(
    {
      deploy: async () => pool,
      supply: BigNumber.from(0),
      name: `Median Liquidity: ${SYMBOL_UNDERLYING}/${SYMBOL_BASE}`,
      symbol: `MED-${SYMBOL_UNDERLYING}${SYMBOL_BASE}`,
      decimals: 18,
      mintERC20: async (address, amount) =>
        pool['mint(address,uint256)'](address, amount),
      burnERC20: async (address, amount) =>
        pool['burn(address,uint256)'](address, amount),
      mintERC1155: undefined as any,
      burnERC1155: undefined as any,
    },
    ['::ERC1155Enumerable', '#transfer', '#transferFrom'],
  );

  describe('#getPair', function () {
    it('returns pair address', async () => {
      const pairAddr = await pool.getPair();
      expect(pairAddr).to.eq(pair.address);

      const pools = await pair.getPools();
      expect(pools[0]).to.eq(pool.address);
    });
  });

  describe('#getUnderlying', function () {
    it('returns underlying address', async () => {
      const pools = await pair.getPools();

      const callPool = Pool__factory.connect(pools[0], owner);
      const putPool = Pool__factory.connect(pools[1], owner);

      const callUnderlying = await callPool.getUnderlying();
      const putUnderlying = await putPool.getUnderlying();

      expect(callUnderlying).to.eq(asset1.address);
      expect(putUnderlying).to.eq(asset0.address);
    });
  });

  describe('#quote', function () {
    it('returns price for given option parameters');
  });

  describe('#deposit', function () {
    it('returns share tokens granted to sender', async () => {
      await underlying.mint(owner.address, 100);
      await underlying.approve(pool.address, ethers.constants.MaxUint256);
      await expect(() => pool.deposit('100')).to.changeTokenBalance(
        underlying,
        owner,
        -100,
      );
      expect(await pool['balanceOf(address)'](owner.address)).to.eq(100);
    });

    it('todo');
  });

  describe('#withdraw', function () {
    it('should fail withdrawing if < 1 day after deposit', async () => {
      await poolUtil.depositLiquidity(owner, underlying, 100);

      await expect(pool.withdraw('100')).to.be.revertedWith(
        'Pool: liquidity must remain locked for 1 day',
      );

      await setTimestamp(getCurrentTimestamp() + 23 * 3600);
      await expect(pool.withdraw('100')).to.be.revertedWith(
        'Pool: liquidity must remain locked for 1 day',
      );
    });

    it('should return underlying tokens withdrawn by sender', async () => {
      await poolUtil.depositLiquidity(owner, underlying, 100);
      expect(await underlying.balanceOf(owner.address)).to.eq(0);

      await setTimestamp(getCurrentTimestamp() + 24 * 3600 + 60);
      await pool.withdraw('100');
      expect(await underlying.balanceOf(owner.address)).to.eq(100);
      expect(await pool['balanceOf(address)'](owner.address)).to.eq(0);
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
      ).to.be.revertedWith(
        'Pool: maturity must be at least 1 day in the future',
      );
    });

    it('should revert if using a maturity more than 28 days in the future', async () => {
      await poolUtil.depositLiquidity(owner, underlying, parseEther('100'));
      const maturity = poolUtil.getMaturity(30);
      const strikePrice = fixedFromFloat(1.5);

      await expect(
        pool
          .connect(buyer)
          .purchase(maturity, strikePrice, parseEther('1'), parseEther('100')),
      ).to.be.revertedWith(
        'Pool: maturity must be at most 28 days in the future',
      );
    });

    it('should revert if using a maturity not corresponding to end of UTC day', async () => {
      await poolUtil.depositLiquidity(owner, underlying, parseEther('100'));
      const maturity = poolUtil.getMaturity(10).add(3600);
      const strikePrice = fixedFromFloat(1.5);

      await expect(
        pool
          .connect(buyer)
          .purchase(maturity, strikePrice, parseEther('1'), parseEther('100')),
      ).to.be.revertedWith('Pool: maturity must correspond to end of UTC day');
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
