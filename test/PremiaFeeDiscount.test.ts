import { expect } from 'chai';
import {
  PremiaFeeDiscount,
  PremiaFeeDiscount__factory,
  PremiaStaking,
  PremiaStaking__factory,
  TestErc20,
  TestErc20__factory,
  TestNewPremiaFeeDiscount__factory,
} from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat, setTimestamp } from './utils/evm';
import { signERC2612Permit } from './eth-permit/eth-permit';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let premia: TestErc20;
let xPremia: PremiaStaking;
let premiaFeeDiscount: PremiaFeeDiscount;

const stakeAmount = ethers.utils.parseEther('120000');
const oneMonth = 30 * 24 * 3600;

describe('PremiaFeeDiscount', () => {
  beforeEach(async () => {
    await resetHardhat();
    [admin, user1] = await ethers.getSigners();

    const premiaFactory = new TestErc20__factory(admin);
    const xPremiaFactory = new PremiaStaking__factory(admin);
    const premiaFeeDiscountFactory = new PremiaFeeDiscount__factory(admin);

    premia = await premiaFactory.deploy();
    xPremia = await xPremiaFactory.deploy(premia.address);
    premiaFeeDiscount = await premiaFeeDiscountFactory.deploy(xPremia.address);

    await premiaFeeDiscount.setStakeLevels([
      { amount: ethers.utils.parseEther('5000'), discount: 9000 }, // 90% of fee (= -10%)
      { amount: ethers.utils.parseEther('50000'), discount: 7500 }, // 75% of fee (= -25%)
      { amount: ethers.utils.parseEther('250000'), discount: 2500 }, // 25% of fee (= -75%)
      { amount: ethers.utils.parseEther('500000'), discount: 1000 }, // 10% of fee (= -90%)
    ]);

    await premiaFeeDiscount.setStakePeriod(oneMonth, 10000);
    await premiaFeeDiscount.setStakePeriod(3 * oneMonth, 12500);
    await premiaFeeDiscount.setStakePeriod(6 * oneMonth, 15000);
    await premiaFeeDiscount.setStakePeriod(12 * oneMonth, 20000);

    await premia.mint(user1.address, stakeAmount);
    await premia.connect(user1).increaseAllowance(xPremia.address, stakeAmount);
    await xPremia.connect(user1).enter(stakeAmount);
    await xPremia
      .connect(user1)
      .increaseAllowance(premiaFeeDiscount.address, stakeAmount);
  });

  it('should correctly overwrite existing stake levels', async () => {
    await premiaFeeDiscount.setStakeLevels([
      { amount: ethers.utils.parseEther('5000'), discount: 8000 },
      { amount: ethers.utils.parseEther('25000'), discount: 4000 },
      { amount: ethers.utils.parseEther('50000'), discount: 2000 },
    ]);

    const length = await premiaFeeDiscount.stakeLevelsLength();
    expect(length).to.eq(3);

    const level0 = await premiaFeeDiscount.stakeLevels(0);
    const level1 = await premiaFeeDiscount.stakeLevels(1);
    const level2 = await premiaFeeDiscount.stakeLevels(2);

    expect(level0.amount).to.eq(ethers.utils.parseEther('5000'));
    expect(level1.amount).to.eq(ethers.utils.parseEther('25000'));
    expect(level2.amount).to.eq(ethers.utils.parseEther('50000'));

    expect(level0.discount).to.eq(8000);
    expect(level1.discount).to.eq(4000);
    expect(level2.discount).to.eq(2000);
  });

  it('should fail staking if stake period does not exists', async () => {
    await expect(
      premiaFeeDiscount.connect(user1).stake(stakeAmount, 2 * oneMonth),
    ).to.be.revertedWith('Stake period does not exists');
  });

  it('should stake and calculate discount successfully', async () => {
    await premiaFeeDiscount.connect(user1).stake(stakeAmount, 3 * oneMonth);
    let amountWithBonus = await premiaFeeDiscount.getStakeAmountWithBonus(
      user1.address,
    );
    expect(amountWithBonus).to.eq(ethers.utils.parseEther('150000'));
    expect(await premiaFeeDiscount.getDiscount(user1.address)).to.eq(5000);

    const newTimestamp = new Date().getTime() / 1000 + 91 * 24 * 3600;
    await setTimestamp(newTimestamp);
    await premiaFeeDiscount
      .connect(user1)
      .unstake(ethers.utils.parseEther('10000'));

    amountWithBonus = await premiaFeeDiscount.getStakeAmountWithBonus(
      user1.address,
    );

    expect(amountWithBonus).to.eq(ethers.utils.parseEther('137500'));
    expect(await premiaFeeDiscount.getDiscount(user1.address)).to.eq(5313);
  });

  it('should stake successfully with permit', async () => {
    await xPremia.connect(user1).approve(premiaFeeDiscount.address, 0);
    const deadline = Math.floor(new Date().getTime() / 1000 + 3600);

    const result = await signERC2612Permit(
      user1.provider,
      xPremia.address,
      user1.address,
      premiaFeeDiscount.address,
      stakeAmount.toString(),
      deadline,
    );

    await premiaFeeDiscount
      .connect(user1)
      .stakeWithPermit(
        stakeAmount,
        3 * oneMonth,
        deadline,
        result.v,
        result.r,
        result.s,
      );

    const amountWithBonus = await premiaFeeDiscount.getStakeAmountWithBonus(
      user1.address,
    );
    expect(amountWithBonus).to.eq(ethers.utils.parseEther('150000'));
  });

  it('should fail unstaking if stake is still locked', async () => {
    await premiaFeeDiscount.connect(user1).stake(stakeAmount, oneMonth);
    await expect(
      premiaFeeDiscount.connect(user1).unstake(1),
    ).to.be.revertedWith('Stake still locked');
  });

  it('should allow unstaking if stake is still locked but stakePeriod has been disabled', async () => {
    await premiaFeeDiscount.connect(user1).stake(stakeAmount, oneMonth);
    await premiaFeeDiscount.connect(admin).setStakePeriod(oneMonth, 0);
    await premiaFeeDiscount.connect(user1).unstake(stakeAmount);
    expect(
      await premiaFeeDiscount.getStakeAmountWithBonus(user1.address),
    ).to.eq(0);
    expect(await xPremia.balanceOf(user1.address)).to.eq(stakeAmount);
  });

  it('should not allow adding to stake with smaller period than period of stake left', async () => {
    await premiaFeeDiscount
      .connect(user1)
      .stake(stakeAmount.div(2), 3 * oneMonth);
    const newTimestamp = new Date().getTime() / 1000 + oneMonth;
    await setTimestamp(newTimestamp);

    // Fail setting one month stake
    await expect(
      premiaFeeDiscount.connect(user1).stake(stakeAmount.div(4), oneMonth),
    ).to.be.revertedWith('Cannot add stake with lower stake period');

    // Success adding 3 months stake
    await premiaFeeDiscount
      .connect(user1)
      .stake(stakeAmount.div(4), 3 * oneMonth);
    let userInfo = await premiaFeeDiscount.userInfo(user1.address);
    expect(userInfo.balance).to.eq(stakeAmount.div(4).mul(3));
    expect(userInfo.stakePeriod).to.eq(3 * oneMonth);

    // Success adding for 6 months stake
    await premiaFeeDiscount
      .connect(user1)
      .stake(stakeAmount.div(4), 6 * oneMonth);
    userInfo = await premiaFeeDiscount.userInfo(user1.address);
    expect(userInfo.balance).to.eq(stakeAmount);
    expect(userInfo.stakePeriod).to.eq(6 * oneMonth);
  });

  it('should fail migration if migration contract not set', async () => {
    await expect(premiaFeeDiscount.migrateStake()).to.be.revertedWith(
      'Migration disabled',
    );
  });

  it('should migrate stake successfully to new contract', async () => {
    await premiaFeeDiscount.connect(user1).stake(stakeAmount, 3 * oneMonth);

    const factory = new TestNewPremiaFeeDiscount__factory(admin);
    const newContract = await factory.deploy(
      premiaFeeDiscount.address,
      xPremia.address,
    );
    await premiaFeeDiscount.setNewContract(newContract.address);

    const userInfoOldBefore = await premiaFeeDiscount.userInfo(user1.address);
    expect(userInfoOldBefore.stakePeriod).to.not.eq(0);
    expect(userInfoOldBefore.lockedUntil).to.not.eq(0);
    expect(userInfoOldBefore.balance).to.not.eq(0);

    await premiaFeeDiscount.connect(user1).migrateStake();

    const userInfoOldAfter = await premiaFeeDiscount.userInfo(user1.address);
    const userInfoNew = await newContract.userInfo(user1.address);

    expect(userInfoOldAfter.stakePeriod).to.eq(0);
    expect(userInfoOldAfter.lockedUntil).to.eq(0);
    expect(userInfoOldAfter.balance).to.eq(0);

    expect(userInfoNew.stakePeriod).to.eq(userInfoOldBefore.stakePeriod);
    expect(userInfoNew.lockedUntil).to.eq(userInfoOldBefore.lockedUntil);
    expect(userInfoNew.balance).to.eq(userInfoOldBefore.balance);
  });
});
