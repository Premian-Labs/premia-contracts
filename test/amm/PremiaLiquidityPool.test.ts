import { expect } from 'chai';
import {
  PremiaLiquidityPool,
  PremiaLiquidityPool__factory,
  PremiaPoolController,
  PremiaPoolController__factory,
  TestErc20,
  TestErc20__factory,
} from '../../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat } from '../utils/evm';
import { parseEther } from 'ethers/lib/utils';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let controller: PremiaPoolController;
let liqPool: PremiaLiquidityPool;
let token: TestErc20;
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

    [admin, user1] = await ethers.getSigners();
    controller = await new PremiaPoolController__factory(admin).deploy();
    liqPool = await new PremiaLiquidityPool__factory(admin).deploy(
      controller.address,
    );
    token = await new TestErc20__factory(admin).deploy(18);
    dai = await new TestErc20__factory(admin).deploy(18);

    await controller.addWhitelistedPools([liqPool.address]);

    await token.mint(user1.address, parseEther('1000'));
    await dai.mint(user1.address, parseEther('1000'));
    await token.connect(user1).approve(liqPool.address, parseEther('1000000'));
    await dai.connect(user1).approve(liqPool.address, parseEther('1000000'));
    await liqPool.setPermissions(
      [token.address, dai.address],
      [
        {
          canBorrow: false,
          canWrite: false,
          isWhitelistedRouter: false,
          isWhitelistedToken: true,
        },
        {
          canBorrow: false,
          canWrite: false,
          isWhitelistedRouter: false,
          isWhitelistedToken: true,
        },
      ],
    );
  });

  describe('deposits', () => {
    it('should fail depositing token if token is not whitelisted', async () => {
      await liqPool.setPermissions(
        [token.address],
        [
          {
            canBorrow: false,
            canWrite: false,
            isWhitelistedRouter: false,
            isWhitelistedToken: false,
          },
        ],
      );
      await expect(
        controller.connect(user1).deposit([
          {
            pool: liqPool.address,
            tokens: [token.address],
            amounts: [parseEther('50')],
            lockExpiration: nextExpiration,
          },
        ]),
      ).to.be.revertedWith('Token not whitelisted');
    });

    it('should successfully deposit tokens', async () => {
      await controller.connect(user1).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther('50'), parseEther('100')],
          lockExpiration: nextExpiration,
        },
      ]);
      const tokenAmount = await liqPool.depositsByUser(
        user1.address,
        token.address,
        nextExpiration,
      );
      const daiAmount = await liqPool.depositsByUser(
        user1.address,
        dai.address,
        nextExpiration,
      );
      expect(tokenAmount).to.eq(parseEther('50'));
      expect(daiAmount).to.eq(parseEther('100'));
    });

    it('should fail deposit if invalid expiration selected', async () => {
      await expect(
        controller.connect(user1).deposit([
          {
            pool: liqPool.address,
            tokens: [token.address],
            amounts: [parseEther('50')],
            lockExpiration: 1200,
          },
        ]),
      ).revertedWith('Exp passed');
      await expect(
        controller.connect(user1).deposit([
          {
            pool: liqPool.address,
            tokens: [token.address],
            amounts: [parseEther('50')],
            lockExpiration: nextExpiration + 55 * oneWeek,
          },
        ]),
      ).revertedWith('Exp > max exp');
      await expect(
        controller.connect(user1).deposit([
          {
            pool: liqPool.address,
            tokens: [token.address],
            amounts: [parseEther('50')],
            lockExpiration: nextExpiration + 1,
          },
        ]),
      ).revertedWith('Wrong exp incr');
    });

    it('should correctly calculate writable amount', async () => {
      await controller.connect(user1).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther('50'), parseEther('100')],
          lockExpiration: nextExpiration,
        },
      ]);
      await controller.connect(user1).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther('20'), parseEther('200')],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      const writableAmount1 = await liqPool.getWritableAmount(
        token.address,
        nextExpiration,
      );
      const writableAmount2 = await liqPool.getWritableAmount(
        token.address,
        nextExpiration + oneWeek,
      );
      const writableAmount3 = await liqPool.getWritableAmount(
        token.address,
        nextExpiration + oneWeek * 2,
      );
      const writableAmount4 = await liqPool.getWritableAmount(
        token.address,
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
});
