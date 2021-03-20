import { expect } from "chai";
import {
  PremiaLiquidityPool,
  PremiaLiquidityPool__factory,
  PremiaMiningV2,
  PremiaMiningV2__factory,
  PremiaPoolController,
  PremiaPoolController__factory,
  TestErc20,
  TestErc20__factory,
} from "../../contractsTyped";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { resetHardhat, setTimestamp } from "../utils/evm";
import { formatEther, parseEther } from "ethers/lib/utils";

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let premia: TestErc20;
let controller: PremiaPoolController;
let liqPool: PremiaLiquidityPool;
let mining: PremiaMiningV2;
let token: TestErc20;
let dai: TestErc20;

const baseExpiration = 172799;
const oneWeek = 7 * 24 * 3600;
const now = new Date().getTime() / 1000;
let nextExpiration = baseExpiration + Math.floor(now / oneWeek) * oneWeek;
if (now > nextExpiration) {
  nextExpiration += oneWeek;
}

describe("PremiaLiquidityPool", () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, user2] = await ethers.getSigners();
    premia = await new TestErc20__factory(admin).deploy(18);
    controller = await new PremiaPoolController__factory(admin).deploy();
    liqPool = await new PremiaLiquidityPool__factory(admin).deploy(
      controller.address
    );
    mining = await new PremiaMiningV2__factory(admin).deploy(
      controller.address,
      premia.address
    );

    token = await new TestErc20__factory(admin).deploy(18);
    dai = await new TestErc20__factory(admin).deploy(18);

    await controller.setPremiaMining(mining.address);
    await mining.setTokenWeights([dai.address, token.address], [1000, 1000]);
    await premia.mint(admin.address, parseEther("1000000"));
    await premia.connect(admin).approve(mining.address, parseEther("1000000"));
    await mining.connect(admin).addRewards(parseEther("1000000"));

    await controller.addWhitelistedPools([liqPool.address]);

    for (const u of [user1, user2]) {
      await token.mint(u.address, parseEther("1000"));
      await dai.mint(u.address, parseEther("1000"));
      await token.connect(u).approve(liqPool.address, parseEther("1000000"));
      await dai.connect(u).approve(liqPool.address, parseEther("1000000"));
    }

    await liqPool.setPermissions(
      [token.address, dai.address],
      [
        {
          canBorrow: false,
          canWrite: false,
          isWhitelistedToken: true,
        },
        {
          canBorrow: false,
          canWrite: false,
          isWhitelistedToken: true,
        },
      ]
    );
  });

  describe("deposits", () => {
    it("should fail depositing token if token is not whitelisted", async () => {
      await liqPool.setPermissions(
        [token.address],
        [
          {
            canBorrow: false,
            canWrite: false,
            isWhitelistedToken: false,
          },
        ]
      );
      await expect(
        controller.connect(user1).deposit([
          {
            pool: liqPool.address,
            tokens: [token.address],
            amounts: [parseEther("50")],
            lockExpiration: nextExpiration,
          },
        ])
      ).to.be.revertedWith("Token not whitelisted");
    });

    it("should successfully deposit tokens", async () => {
      await controller.connect(user1).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther("50"), parseEther("100")],
          lockExpiration: nextExpiration,
        },
      ]);
      const tokenAmount = await liqPool.depositsByUser(
        user1.address,
        token.address,
        nextExpiration
      );
      const daiAmount = await liqPool.depositsByUser(
        user1.address,
        dai.address,
        nextExpiration
      );
      expect(tokenAmount).to.eq(parseEther("50"));
      expect(daiAmount).to.eq(parseEther("100"));
    });

    it("should fail deposit if invalid expiration selected", async () => {
      await expect(
        controller.connect(user1).deposit([
          {
            pool: liqPool.address,
            tokens: [token.address],
            amounts: [parseEther("50")],
            lockExpiration: 1200,
          },
        ])
      ).revertedWith("Exp passed");
      await expect(
        controller.connect(user1).deposit([
          {
            pool: liqPool.address,
            tokens: [token.address],
            amounts: [parseEther("50")],
            lockExpiration: nextExpiration + 55 * oneWeek,
          },
        ])
      ).revertedWith("Exp > max exp");
      await expect(
        controller.connect(user1).deposit([
          {
            pool: liqPool.address,
            tokens: [token.address],
            amounts: [parseEther("50")],
            lockExpiration: nextExpiration + 1,
          },
        ])
      ).revertedWith("Wrong exp incr");
    });

    it("should correctly calculate writable amount", async () => {
      await controller.connect(user1).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther("50"), parseEther("100")],
          lockExpiration: nextExpiration,
        },
      ]);
      await controller.connect(user1).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther("20"), parseEther("200")],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      const writableAmount1 = await liqPool.getWritableAmount(
        token.address,
        nextExpiration
      );
      const writableAmount2 = await liqPool.getWritableAmount(
        token.address,
        nextExpiration + oneWeek
      );
      const writableAmount3 = await liqPool.getWritableAmount(
        token.address,
        nextExpiration + oneWeek * 2
      );
      const writableAmount4 = await liqPool.getWritableAmount(
        token.address,
        nextExpiration + oneWeek * 3
      );

      // console.log(writableAmount1)
      // console.log(await liqPool.hasWritableAmount(token.address, nextExpiration, parseEther('60')));

      expect(writableAmount1).to.eq(parseEther("70"));
      expect(writableAmount2).to.eq(parseEther("20"));
      expect(writableAmount3).to.eq(parseEther("20"));
      expect(writableAmount4).to.eq(0);
    });
  });

  describe("PremiaMiningV2", () => {
    it("should have properly added premia reward", async () => {
      expect(await premia.balanceOf(mining.address)).to.eq(
        parseEther("1000000")
      );
      expect(await mining.totalPremiaAdded()).to.eq(parseEther("1000000"));
    });

    it("should properly harvest rewards", async () => {
      await controller.connect(user1).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther("50"), parseEther("100")],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      const now = new Date().getTime() / 1000;
      await setTimestamp(now + 4 * 3600 * 24);

      await mining.connect(user1).harvest();

      let user1Bal = await premia.balanceOf(user1.address);
      let user2Bal = await premia.balanceOf(user2.address);

      expect(
        user1Bal.gt(parseEther("39995")) && user1Bal.lt(parseEther("40000"))
      ).to.be.true;

      await controller.connect(user2).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther("150"), parseEther("300")],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      await setTimestamp(now + 8 * 3600 * 24);

      await mining.connect(user1).harvest();
      await mining.connect(user2).harvest();

      user1Bal = await premia.balanceOf(user1.address);
      user2Bal = await premia.balanceOf(user2.address);

      // The inaccuracy is because of the bonus for longer staking from the first deposit made
      expect(
        user1Bal.gt(parseEther("50000")) && user1Bal.lt(parseEther("50100"))
      ).to.be.true;

      expect(
        user2Bal.gt(parseEther("29900")) && user2Bal.lt(parseEther("30000"))
      ).to.be.true;
    });

    it("should properly calculate pending reward", async () => {
      await controller.connect(user1).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther("50"), parseEther("100")],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      const now = new Date().getTime() / 1000;
      await setTimestamp(now + 4 * 3600 * 24);

      let user1Bal = await mining.pendingReward(user1.address);
      let user2Bal = await mining.pendingReward(user2.address);

      expect(
        user1Bal.gt(parseEther("39995")) && user1Bal.lt(parseEther("40000"))
      ).to.be.true;

      await controller.connect(user2).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther("150"), parseEther("300")],
          lockExpiration: nextExpiration + oneWeek * 2,
        },
      ]);

      await setTimestamp(now + 8 * 3600 * 24);

      user1Bal = await mining.pendingReward(user1.address);
      user2Bal = await mining.pendingReward(user2.address);

      // The inaccuracy is because of the bonus for longer staking from the first deposit made
      expect(
        user1Bal.gt(parseEther("50000")) && user1Bal.lt(parseEther("50100"))
      ).to.be.true;

      expect(
        user2Bal.gt(parseEther("29900")) && user2Bal.lt(parseEther("30000"))
      ).to.be.true;
    });

    it("should stop distributing premia when allocated amount is reached", async () => {
      await controller.connect(user1).deposit([
        {
          pool: liqPool.address,
          tokens: [token.address, dai.address],
          amounts: [parseEther("50"), parseEther("100")],
          lockExpiration: nextExpiration + oneWeek * 50,
        },
      ]);

      const now = new Date().getTime() / 1000;

      await setTimestamp(now + 110 * 3600 * 24);

      let amount = await mining.pendingReward(user1.address);

      expect(
        amount.gt(parseEther("999999.99")) && amount.lte(parseEther("1000000"))
      ).to.be.true;

      await mining.connect(user1).harvest();

      amount = await premia.balanceOf(user1.address);

      expect(
        amount.gt(parseEther("999999.99")) && amount.lte(parseEther("1000000"))
      ).to.be.true;

      await premia.mint(admin.address, parseEther("200000"));
      await premia.connect(admin).approve(mining.address, parseEther("200000"));
      await mining.connect(admin).addRewards(parseEther("200000"));

      await setTimestamp(now + 131 * 3600 * 24);

      amount = await mining.pendingReward(user1.address);
      expect(
        amount.gt(parseEther("199999.99")) && amount.lte(parseEther("200000"))
      ).to.be.true;

      await mining.connect(user1).harvest();
      amount = await premia.balanceOf(user1.address);

      expect(
        amount.gt(parseEther("1199999.99")) && amount.lte(parseEther("1200000"))
      ).to.be.true;
    });
  });
});
