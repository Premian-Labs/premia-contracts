import { expect } from 'chai';
import {
  PremiaAMM,
  PremiaAMM__factory,
  PremiaLiquidityPool,
  PremiaLongUnderlyingPool,
  PremiaLongUnderlyingPool__factory,
  PremiaMiningV2,
  PremiaMiningV2__factory,
  PremiaShortUnderlyingPool,
  PremiaShortUnderlyingPool__factory,
  TestErc20,
  TestErc20__factory,
} from '../../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat, setTimestamp } from '../utils/evm';
import { formatEther, parseEther } from 'ethers/lib/utils';
import { ZERO_ADDRESS } from '../utils/constants';

const chai = require('chai');
const chaiAlmost = require('chai-almost');

chai.use(chaiAlmost(0.2));

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let premia: TestErc20;
let controller: PremiaAMM;
let longPool: PremiaLongUnderlyingPool;
let shortPool: PremiaShortUnderlyingPool;
let mining: PremiaMiningV2;
let token1: TestErc20;
let token2: TestErc20;
let dai: TestErc20;

const baseExpiration = 172799;
const oneWeek = 7 * 24 * 3600;
const now = new Date().getTime() / 1000;
let nextExpiration = baseExpiration + Math.floor(now / oneWeek) * oneWeek;
if (now > nextExpiration) {
  nextExpiration += oneWeek;
}

describe('PremiaLiquidityPool', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, user2] = await ethers.getSigners();
    premia = await new TestErc20__factory(admin).deploy(18);
    token1 = await new TestErc20__factory(admin).deploy(18);
    token2 = await new TestErc20__factory(admin).deploy(18);
    dai = await new TestErc20__factory(admin).deploy(18);

    controller = await new PremiaAMM__factory(admin).deploy();

    longPool = await new PremiaLongUnderlyingPool__factory(admin).deploy(
      controller.address,
      ZERO_ADDRESS,
      ZERO_ADDRESS,
    );
    shortPool = await new PremiaShortUnderlyingPool__factory(admin).deploy(
      controller.address,
      ZERO_ADDRESS,
      ZERO_ADDRESS,
    );

    await controller.addPools([longPool.address], [shortPool.address]);

    mining = await new PremiaMiningV2__factory(admin).deploy(
      controller.address,
      premia.address,
    );

    await controller.setPremiaMining(mining.address);
    await mining.setPool(token2.address, 1000, false);
    await mining.setPool(token1.address, 1000, false);
    await premia.mint(admin.address, parseEther('1000000'));
    await premia.connect(admin).approve(mining.address, parseEther('1000000'));
    await mining.connect(admin).addRewards(parseEther('1000000'));

    await longPool.setPermissions(
      [token1.address, token2.address],
      [
        {
          canBorrow: false,
          isWhitelistedToken: true,
          isWhitelistedOptionContract: false,
        },
        {
          canBorrow: false,
          isWhitelistedToken: true,
          isWhitelistedOptionContract: false,
        },
      ],
    );

    for (const u of [user1, user2]) {
      await token1.mint(u.address, parseEther('1000'));
      await token2.mint(u.address, parseEther('1000'));
      await token1.connect(u).approve(longPool.address, parseEther('1000000'));
      await token2.connect(u).approve(longPool.address, parseEther('1000000'));
    }
  });

  describe('deposits', () => {
    it('should fail depositing if pool is not whitelisted', async () => {
      await controller.removePools([longPool.address], []);
      await expect(
        controller.connect(user1).depositLiquidity([
          {
            pool: longPool.address,
            tokens: [token1.address],
            amounts: [parseEther('50')],
            lockExpiration: nextExpiration,
          },
        ]),
      ).to.be.revertedWith('Pool not whitelisted');
    });

    it('should fail depositing token if token is not whitelisted', async () => {
      await longPool.setPermissions(
        [token1.address],
        [
          {
            canBorrow: false,
            isWhitelistedToken: false,
            isWhitelistedOptionContract: false,
          },
        ],
      );
      await expect(
        controller.connect(user1).depositLiquidity([
          {
            pool: longPool.address,
            tokens: [token1.address],
            amounts: [parseEther('50')],
            lockExpiration: nextExpiration,
          },
        ]),
      ).to.be.revertedWith('Token not whitelisted');
    });

    it('should successfully deposit tokens', async () => {
      await controller.connect(user1).depositLiquidity([
        {
          pool: longPool.address,
          tokens: [token1.address, token2.address],
          amounts: [parseEther('50'), parseEther('100')],
          lockExpiration: nextExpiration,
        },
      ]);
      const tokenAmount = await longPool.userInfos(
        user1.address,
        token1.address,
        nextExpiration,
      );
      const daiAmount = await longPool.userInfos(
        user1.address,
        token2.address,
        nextExpiration,
      );
      expect(tokenAmount.amount).to.eq(parseEther('50'));
      expect(daiAmount.amount).to.eq(parseEther('100'));
    });

    it('should fail deposit if invalid expiration selected', async () => {
      await expect(
        controller.connect(user1).depositLiquidity([
          {
            pool: longPool.address,
            tokens: [token1.address],
            amounts: [parseEther('50')],
            lockExpiration: 1200,
          },
        ]),
      ).revertedWith('Exp passed');
      await expect(
        controller.connect(user1).depositLiquidity([
          {
            pool: longPool.address,
            tokens: [token1.address],
            amounts: [parseEther('50')],
            lockExpiration: nextExpiration + 55 * oneWeek,
          },
        ]),
      ).revertedWith('Exp > max exp');
      await expect(
        controller.connect(user1).depositLiquidity([
          {
            pool: longPool.address,
            tokens: [token1.address],
            amounts: [parseEther('50')],
            lockExpiration: nextExpiration + 1,
          },
        ]),
      ).revertedWith('Wrong exp incr');
    });

    it('should correctly calculate writable amount', async () => {
      await controller.connect(user1).depositLiquidity([
        {
          pool: longPool.address,
          tokens: [token1.address, token2.address],
          amounts: [parseEther('50'), parseEther('100')],
          lockExpiration: nextExpiration,
        },
      ]);
      await controller.connect(user1).depositLiquidity([
        {
          pool: longPool.address,
          tokens: [token1.address, token2.address],
          amounts: [parseEther('20'), parseEther('200')],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      const writableAmount1 = await longPool.getWritableAmount(
        token1.address,
        nextExpiration,
      );
      const writableAmount2 = await longPool.getWritableAmount(
        token1.address,
        nextExpiration + oneWeek,
      );
      const writableAmount3 = await longPool.getWritableAmount(
        token1.address,
        nextExpiration + oneWeek * 2,
      );
      const writableAmount4 = await longPool.getWritableAmount(
        token1.address,
        nextExpiration + oneWeek * 3,
      );

      // console.log(writableAmount1)
      // console.log(await liqPool.hasWritableAmount(token.address, nextExpiration, parseEther('60')));

      expect(writableAmount1).to.eq(parseEther('70'));
      expect(writableAmount2).to.eq(parseEther('20'));
      expect(writableAmount3).to.eq(parseEther('20'));
      expect(writableAmount4).to.eq(0);
    });
  });

  describe('PremiaMiningV2', () => {
    it('should have properly added premia reward', async () => {
      expect(await premia.balanceOf(mining.address)).to.eq(
        parseEther('1000000'),
      );
      expect(await mining.totalPremiaAdded()).to.eq(parseEther('1000000'));
    });

    it('should properly harvest rewards', async () => {
      await controller.connect(user1).depositLiquidity([
        {
          pool: longPool.address,
          tokens: [token1.address, token2.address],
          amounts: [parseEther('50'), parseEther('150')],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      const now = new Date().getTime() / 1000;
      await setTimestamp(now + 4 * 3600 * 24);

      await mining.connect(user1).harvest([token1.address]);
      await mining.connect(user1).harvest([token2.address]);

      let user1PremiaBal = await premia.balanceOf(user1.address);
      let user2PremiaBal = await premia.balanceOf(user2.address);

      expect(
        user1PremiaBal.gt(parseEther('39995')) &&
          user1PremiaBal.lt(parseEther('40000')),
      ).to.be.true;

      await controller.connect(user2).depositLiquidity([
        {
          pool: longPool.address,
          tokens: [token1.address, token2.address],
          amounts: [parseEther('150'), parseEther('150')],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      const tokenTotalScore = (await mining.poolInfo(token1.address))
        .totalScore;
      const user1TokenScore = (
        await mining.userInfo(token1.address, user1.address)
      ).totalScore;

      const daiTotalScore = (await mining.poolInfo(token2.address)).totalScore;
      const user1DaiScore = (
        await mining.userInfo(token2.address, user1.address)
      ).totalScore;

      await setTimestamp(now + 8 * 3600 * 24);

      const multToken =
        Number(formatEther(user1TokenScore)) /
        Number(formatEther(tokenTotalScore));
      const multDai =
        Number(formatEther(user1DaiScore)) / Number(formatEther(daiTotalScore));

      let user1TokenTargetBal = 20000 * multToken;
      let user2TokenTargetBal = 20000 * (1 - multToken);

      let user1DaiTargetBal = 20000 * multDai;
      let user2DaiTargetBal = 20000 * (1 - multDai);

      await mining.connect(user1).harvest([token1.address, token2.address]);
      await mining.connect(user2).harvest([token1.address, token2.address]);

      const user1PremiaBalBak = user1PremiaBal;

      user1PremiaBal = await premia.balanceOf(user1.address);
      user2PremiaBal = await premia.balanceOf(user2.address);

      expect(Number(formatEther(user1PremiaBal))).to.almost.eq(
        user1TokenTargetBal +
          user1DaiTargetBal +
          Number(formatEther(user1PremiaBalBak)),
      );

      expect(Number(formatEther(user2PremiaBal))).to.almost.eq(
        user2DaiTargetBal + user2TokenTargetBal,
      );
    });

    it('should properly calculate pending reward', async () => {
      await controller.connect(user1).depositLiquidity([
        {
          pool: longPool.address,
          tokens: [token1.address, token2.address],
          amounts: [parseEther('50'), parseEther('150')],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      const now = new Date().getTime() / 1000;
      await setTimestamp(now + 4 * 3600 * 24);

      let user1TokenBal = await mining.pendingReward(
        user1.address,
        token1.address,
      );
      let user2TokenBal = await mining.pendingReward(
        user2.address,
        token1.address,
      );
      let user1DaiBal = await mining.pendingReward(
        user1.address,
        token2.address,
      );
      let user2DaiBal = await mining.pendingReward(
        user2.address,
        token2.address,
      );

      expect(
        user1TokenBal.gt(parseEther('19995')) &&
          user1TokenBal.lt(parseEther('20000')),
      ).to.be.true;
      expect(
        user1DaiBal.gt(parseEther('19995')) &&
          user1DaiBal.lt(parseEther('20000')),
      ).to.be.true;

      await controller.connect(user2).depositLiquidity([
        {
          pool: longPool.address,
          tokens: [token1.address, token2.address],
          amounts: [parseEther('150'), parseEther('150')],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      const tokenTotalScore = (await mining.poolInfo(token1.address))
        .totalScore;
      const user1TokenScore = (
        await mining.userInfo(token1.address, user1.address)
      ).totalScore;

      const daiTotalScore = (await mining.poolInfo(token2.address)).totalScore;
      const user1DaiScore = (
        await mining.userInfo(token2.address, user1.address)
      ).totalScore;

      await setTimestamp(now + 8 * 3600 * 24);

      const multToken =
        Number(formatEther(user1TokenScore)) /
        Number(formatEther(tokenTotalScore));
      const multDai =
        Number(formatEther(user1DaiScore)) / Number(formatEther(daiTotalScore));

      let user1TokenTargetBal =
        Number(formatEther(user1TokenBal)) + 20000 * multToken;
      let user2TokenTargetBal = 20000 * (1 - multToken);

      let user1DaiTargetBal =
        Number(formatEther(user1DaiBal)) + 20000 * multDai;
      let user2DaiTargetBal = 20000 * (1 - multDai);

      user1TokenBal = await mining.pendingReward(user1.address, token1.address);
      user2TokenBal = await mining.pendingReward(user2.address, token1.address);
      user1DaiBal = await mining.pendingReward(user1.address, token2.address);
      user2DaiBal = await mining.pendingReward(user2.address, token2.address);

      expect(Number(formatEther(user1TokenBal))).to.almost.eq(
        user1TokenTargetBal,
      );

      expect(Number(formatEther(user2TokenBal))).to.almost.eq(
        user2TokenTargetBal,
      );

      expect(Number(formatEther(user1DaiBal))).to.almost.eq(user1DaiTargetBal);

      expect(Number(formatEther(user2DaiBal))).to.almost.eq(user2DaiTargetBal);
    });

    it('should stop distributing premia when allocated amount is reached', async () => {
      await controller.connect(user1).depositLiquidity([
        {
          pool: longPool.address,
          tokens: [token1.address],
          amounts: [parseEther('50')],
          lockExpiration: nextExpiration + oneWeek * 50,
        },
      ]);
      await mining.connect(admin).setPool(token2.address, 0, false);

      const now = new Date().getTime() / 1000;

      await setTimestamp(now + 110 * 3600 * 24);

      let amount = await mining.pendingReward(user1.address, token1.address);

      expect(
        amount.gt(parseEther('999999.99')) && amount.lte(parseEther('1000000')),
      ).to.be.true;

      await mining.connect(user1).harvest([token1.address]);

      amount = await premia.balanceOf(user1.address);

      expect(
        amount.gt(parseEther('999999.99')) && amount.lte(parseEther('1000000')),
      ).to.be.true;

      await premia.mint(admin.address, parseEther('200000'));
      await premia.connect(admin).approve(mining.address, parseEther('200000'));
      await mining.connect(admin).addRewards(parseEther('200000'));

      await setTimestamp(now + 131 * 3600 * 24);

      amount = await mining.pendingReward(user1.address, token1.address);
      expect(
        amount.gt(parseEther('199999.99')) && amount.lte(parseEther('200000')),
      ).to.be.true;

      await mining.connect(user1).harvest([token1.address]);
      amount = await premia.balanceOf(user1.address);

      expect(
        amount.gt(parseEther('1199999.99')) &&
          amount.lte(parseEther('1200000')),
      ).to.be.true;
    });
  });
});
