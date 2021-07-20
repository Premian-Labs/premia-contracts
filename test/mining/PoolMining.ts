import chai, { expect } from 'chai';
import { PoolUtil } from '../pool/PoolUtil';
import {
  increaseTimestamp,
  mineBlock,
  mineBlockUntil,
  resetHardhat,
} from '../utils/evm';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  ERC20Mock,
  ERC20Mock__factory,
  PremiaFeeDiscount,
  PremiaFeeDiscount__factory,
} from '../../typechain';
import { parseEther } from 'ethers/lib/utils';
import { bnToNumber } from '../utils/math';
import chaiAlmost from 'chai-almost';

chai.use(chaiAlmost(0.01));

const oneMonth = 30 * 24 * 3600;

describe('PoolMining', () => {
  let owner: SignerWithAddress;
  let lp1: SignerWithAddress;
  let lp2: SignerWithAddress;
  let lp3: SignerWithAddress;
  let buyer: SignerWithAddress;
  let feeReceiver: SignerWithAddress;

  let premia: ERC20Mock;
  let xPremia: ERC20Mock;
  let premiaFeeDiscount: PremiaFeeDiscount;

  let p: PoolUtil;

  const spotPrice = 2000;
  const totalRewardAmount = 200000;

  beforeEach(async () => {
    await resetHardhat();
    [owner, lp1, lp2, lp3, buyer, feeReceiver] = await ethers.getSigners();

    const erc20Factory = new ERC20Mock__factory(owner);
    premia = await erc20Factory.deploy('PREMIA', 18);
    xPremia = await erc20Factory.deploy('xPREMIA', 18);
    premiaFeeDiscount = await new PremiaFeeDiscount__factory(owner).deploy(
      xPremia.address,
    );

    await premiaFeeDiscount.setStakeLevels([
      { amount: parseEther('5000'), discount: 2500 }, // -25%
      { amount: parseEther('50000'), discount: 5000 }, // -50%
      { amount: parseEther('250000'), discount: 7500 }, // -75%
      { amount: parseEther('500000'), discount: 9500 }, // -95%
    ]);

    await premiaFeeDiscount.setStakePeriod(oneMonth, 10000);
    await premiaFeeDiscount.setStakePeriod(3 * oneMonth, 12500);
    await premiaFeeDiscount.setStakePeriod(6 * oneMonth, 15000);
    await premiaFeeDiscount.setStakePeriod(12 * oneMonth, 20000);

    p = await PoolUtil.deploy(
      owner,
      premia.address,
      spotPrice,
      feeReceiver.address,
      premiaFeeDiscount.address,
    );

    await premia.mint(owner.address, parseEther(totalRewardAmount.toString()));
    await premia
      .connect(owner)
      .approve(p.poolMining.address, ethers.constants.MaxUint256);
    await p.poolMining.addPremiaRewards(
      parseEther(totalRewardAmount.toString()),
    );

    for (const lp of [lp1, lp2, lp3]) {
      for (const token of [p.underlying, p.base]) {
        await token.mint(lp.address, parseEther('100'));
        await token
          .connect(lp)
          .approve(p.pool.address, ethers.constants.MaxUint256);
      }
    }
  });

  it('should revert if calling update not from the option pool', async () => {
    await expect(
      p.poolMining.updatePool(p.pool.address, true, parseEther('1')),
    ).to.be.revertedWith('Not pool');
  });

  it('should distribute PREMIA properly for each LP', async () => {
    await mineBlockUntil(99);
    await p.pool.connect(lp1).deposit(parseEther('10'), false);

    await mineBlockUntil(109);
    // LP1 deposits 10 at block 100
    await p.pool.connect(lp1).deposit(parseEther('10'), true);

    // LP2 deposits 20 at block 114
    await mineBlockUntil(113);
    await p.pool.connect(lp2).deposit(parseEther('20'), true);

    // There is 4 pools with equal alloc points, with premia reward of 4k per block
    // Each pool should get 1k reward per block. Lp1 should therefore have 4 * 1000 pending reward now
    expect(
      await p.poolMining.pendingPremia(p.pool.address, true, lp1.address),
    ).to.eq(parseEther('4000'));

    // LP3 deposits 30 at block 118
    await mineBlockUntil(117);
    await p.pool.connect(lp3).deposit(parseEther('30'), true);

    // LP1 deposits 10 more at block 120. At this point :
    //   LP1 should have pending reward of : 4*1000 + 4*1/3*1000 + 2*1/6*1000 = 5666.66
    await mineBlockUntil(119);
    await p.pool.connect(lp1).deposit(parseEther('10'), true);
    expect(
      bnToNumber(
        await p.poolMining.pendingPremia(p.pool.address, true, lp1.address),
      ),
    ).to.almost(5666.66);

    await increaseTimestamp(25 * 3600);

    // LP2 withdraws 5 LPs at block 130. At this point:
    //     LP2 should have pending reward of: 4*2/3*1000 + 2*2/6*1000 + 10*2/7*1000 = 6190.47
    await mineBlockUntil(129);
    await p.pool.connect(lp2).withdraw(parseEther('5'), true);
    expect(
      bnToNumber(
        await p.poolMining.pendingPremia(p.pool.address, true, lp2.address),
      ),
    ).to.almost(6190.47);

    // LP1 withdraws 20 LPs at block 340.
    // LP2 withdraws 15 LPs at block 350.
    // LP3 withdraws 30 LPs at block 360.
    await mineBlockUntil(139);
    await p.pool.connect(lp1).withdraw(parseEther('20'), true);

    await mineBlockUntil(149);
    await p.pool.connect(lp2).withdraw(parseEther('15'), true);

    await mineBlockUntil(159);
    await p.pool.connect(lp3).withdraw(parseEther('30'), true);

    expect(bnToNumber(await p.poolMining.premiaRewardsAvailable())).to.almost(
      totalRewardAmount - 50000,
    );

    // LP1 should have: 5666 + 10*2/7*1000 + 10*2/6.5*1000 = 11600.73
    expect(
      bnToNumber(
        await p.poolMining.pendingPremia(p.pool.address, true, lp1.address),
      ),
    ).to.almost(11600.73);
    // LP2 should have: 6190 + 10*1.5/6.5 * 1000 + 10*1.5/4.5*1000 = 11831.5
    expect(
      bnToNumber(
        await p.poolMining.pendingPremia(p.pool.address, true, lp2.address),
      ),
    ).to.almost(11831.5);
    // LP3 should have: 2*3/6*1000 + 10*3/7*1000 + 10*3/6.5*1000 + 10*3/4.5*1000 + 10*1000 = 26567.76
    expect(
      bnToNumber(
        await p.poolMining.pendingPremia(p.pool.address, true, lp3.address),
      ),
    ).to.almost(26567.76);
    expect(
      bnToNumber(
        await p.poolMining.pendingPremia(p.pool.address, false, lp1.address),
      ),
    ).to.almost(60000);

    await p.pool.connect(lp1).claimRewards(true);
    await p.pool.connect(lp2).claimRewards(true);
    await p.pool.connect(lp3).claimRewards(true);
    await expect(bnToNumber(await premia.balanceOf(lp1.address))).to.almost(
      11600.73,
    );
    await expect(bnToNumber(await premia.balanceOf(lp2.address))).to.almost(
      11831.5,
    );
    await expect(bnToNumber(await premia.balanceOf(lp3.address))).to.almost(
      26567.76,
    );
  });

  it('should stop distributing rewards if available rewards run out', async () => {
    await p.pool.connect(lp1).deposit(parseEther('10'), true);

    await mineBlockUntil(300);

    expect(
      await p.poolMining.pendingPremia(p.pool.address, true, lp1.address),
    ).to.eq(parseEther(totalRewardAmount.toString()));

    await p.pool.connect(lp1).claimRewards(true);
    expect(await p.poolMining.premiaRewardsAvailable()).to.eq(0);
    expect(await premia.balanceOf(lp1.address)).to.eq(
      parseEther(totalRewardAmount.toString()),
    );

    await mineBlockUntil(320);
    expect(
      await p.poolMining.pendingPremia(p.pool.address, true, lp1.address),
    ).to.eq(0);

    await premia.mint(owner.address, parseEther(totalRewardAmount.toString()));
    await mineBlockUntil(349);
    // Trigger pool update
    await p.pool.connect(lp1).updateMiningPools();
    await p.poolMining
      .connect(owner)
      .addPremiaRewards(parseEther(totalRewardAmount.toString()));

    await mineBlockUntil(360);
    expect(
      bnToNumber(
        await p.poolMining.pendingPremia(p.pool.address, true, lp1.address),
      ),
    ).to.almost(10000);
  });
});
