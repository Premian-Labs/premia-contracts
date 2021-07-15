import { expect } from 'chai';
import {
  PremiaFeeDiscount,
  ERC20Mock,
  TestNewPremiaFeeDiscount__factory,
} from '../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat, setTimestamp } from './utils/evm';
import { signERC2612Permit } from './eth-permit/eth-permit';
import { deployV1, IPremiaContracts } from '../scripts/utils/deployV1';
import { parseEther } from 'ethers/lib/utils';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;

const stakeAmount = parseEther('120000');
const oneMonth = 30 * 24 * 3600;

describe('PremiaFeeDiscount', () => {
  beforeEach(async () => {
    await resetHardhat();
    [admin, user1, treasury] = await ethers.getSigners();

    p = await deployV1(admin, treasury.address, true);

    await p.premiaFeeDiscount.setStakeLevels([
      { amount: parseEther('5000'), discount: 2500 }, // -25%
      { amount: parseEther('50000'), discount: 5000 }, // -50%
      { amount: parseEther('250000'), discount: 7500 }, // -75%
      { amount: parseEther('500000'), discount: 9500 }, // -95%
    ]);

    await p.premiaFeeDiscount.setStakePeriod(oneMonth, 10000);
    await p.premiaFeeDiscount.setStakePeriod(3 * oneMonth, 12500);
    await p.premiaFeeDiscount.setStakePeriod(6 * oneMonth, 15000);
    await p.premiaFeeDiscount.setStakePeriod(12 * oneMonth, 20000);

    await (p.premia as ERC20Mock).mint(user1.address, stakeAmount);
    await p.premia
      .connect(user1)
      .increaseAllowance(p.xPremia.address, stakeAmount);
    await p.xPremia.connect(user1).enter(stakeAmount);
    await p.xPremia
      .connect(user1)
      .increaseAllowance(p.premiaFeeDiscount.address, stakeAmount);
  });

  it('should correctly overwrite existing stake levels', async () => {
    await p.premiaFeeDiscount.setStakeLevels([
      { amount: parseEther('5000'), discount: 2000 },
      { amount: parseEther('25000'), discount: 4000 },
      { amount: parseEther('50000'), discount: 8000 },
    ]);

    const length = await p.premiaFeeDiscount.stakeLevelsLength();
    expect(length).to.eq(3);

    const level0 = await p.premiaFeeDiscount.stakeLevels(0);
    const level1 = await p.premiaFeeDiscount.stakeLevels(1);
    const level2 = await p.premiaFeeDiscount.stakeLevels(2);

    expect(level0.amount).to.eq(parseEther('5000'));
    expect(level1.amount).to.eq(parseEther('25000'));
    expect(level2.amount).to.eq(parseEther('50000'));

    expect(level0.discount).to.eq(2000);
    expect(level1.discount).to.eq(4000);
    expect(level2.discount).to.eq(8000);
  });

  it('should fail staking if stake period does not exists', async () => {
    await expect(
      p.premiaFeeDiscount.connect(user1).stake(stakeAmount, 2 * oneMonth),
    ).to.be.revertedWith('Stake period does not exists');
  });

  it('should stake and calculate discount successfully', async () => {
    await p.premiaFeeDiscount.connect(user1).stake(stakeAmount, 3 * oneMonth);
    let amountWithBonus = await p.premiaFeeDiscount.getStakeAmountWithBonus(
      user1.address,
    );
    expect(amountWithBonus).to.eq(parseEther('150000'));
    expect(await p.premiaFeeDiscount.getDiscount(user1.address)).to.eq(6250);

    const newTimestamp = new Date().getTime() / 1000 + 91 * 24 * 3600;
    await setTimestamp(newTimestamp);
    await p.premiaFeeDiscount.connect(user1).unstake(parseEther('10000'));

    amountWithBonus = await p.premiaFeeDiscount.getStakeAmountWithBonus(
      user1.address,
    );

    expect(amountWithBonus).to.eq(parseEther('137500'));
    expect(await p.premiaFeeDiscount.getDiscount(user1.address)).to.eq(6093);
  });

  it('should stake successfully with permit', async () => {
    await p.xPremia.connect(user1).approve(p.premiaFeeDiscount.address, 0);
    const deadline = Math.floor(new Date().getTime() / 1000 + 3600);

    const result = await signERC2612Permit(
      user1.provider,
      p.xPremia.address,
      user1.address,
      p.premiaFeeDiscount.address,
      stakeAmount.toString(),
      deadline,
    );

    await p.premiaFeeDiscount
      .connect(user1)
      .stakeWithPermit(
        stakeAmount,
        3 * oneMonth,
        deadline,
        result.v,
        result.r,
        result.s,
      );

    const amountWithBonus = await p.premiaFeeDiscount.getStakeAmountWithBonus(
      user1.address,
    );
    expect(amountWithBonus).to.eq(parseEther('150000'));
  });

  it('should fail unstaking if stake is still locked', async () => {
    await p.premiaFeeDiscount.connect(user1).stake(stakeAmount, oneMonth);
    await expect(
      p.premiaFeeDiscount.connect(user1).unstake(1),
    ).to.be.revertedWith('Stake still locked');
  });

  it('should allow unstaking if stake is still locked but stakePeriod has been disabled', async () => {
    await p.premiaFeeDiscount.connect(user1).stake(stakeAmount, oneMonth);
    await p.premiaFeeDiscount.connect(admin).setStakePeriod(oneMonth, 0);
    await p.premiaFeeDiscount.connect(user1).unstake(stakeAmount);
    expect(
      await p.premiaFeeDiscount.getStakeAmountWithBonus(user1.address),
    ).to.eq(0);
    expect(await p.xPremia.balanceOf(user1.address)).to.eq(stakeAmount);
  });

  it('should not allow adding to stake with smaller period than period of stake left', async () => {
    await p.premiaFeeDiscount
      .connect(user1)
      .stake(stakeAmount.div(2), 3 * oneMonth);
    const newTimestamp = new Date().getTime() / 1000 + oneMonth;
    await setTimestamp(newTimestamp);

    // Fail setting one month stake
    await expect(
      p.premiaFeeDiscount.connect(user1).stake(stakeAmount.div(4), oneMonth),
    ).to.be.revertedWith('Cannot add stake with lower stake period');

    // Success adding 3 months stake
    await p.premiaFeeDiscount
      .connect(user1)
      .stake(stakeAmount.div(4), 3 * oneMonth);
    let userInfo = await p.premiaFeeDiscount.userInfo(user1.address);
    expect(userInfo.balance).to.eq(stakeAmount.div(4).mul(3));
    expect(userInfo.stakePeriod).to.eq(3 * oneMonth);

    // Success adding for 6 months stake
    await p.premiaFeeDiscount
      .connect(user1)
      .stake(stakeAmount.div(4), 6 * oneMonth);
    userInfo = await p.premiaFeeDiscount.userInfo(user1.address);
    expect(userInfo.balance).to.eq(stakeAmount);
    expect(userInfo.stakePeriod).to.eq(6 * oneMonth);
  });

  it('should fail migration if migration contract not set', async () => {
    await expect(p.premiaFeeDiscount.migrateStake()).to.be.revertedWith(
      'Migration disabled',
    );
  });

  it('should migrate stake successfully to new contract', async () => {
    await p.premiaFeeDiscount.connect(user1).stake(stakeAmount, 3 * oneMonth);

    const factory = new TestNewPremiaFeeDiscount__factory(admin);
    const newContract = await factory.deploy(
      p.premiaFeeDiscount.address,
      p.xPremia.address,
    );
    await p.premiaFeeDiscount.setNewContract(newContract.address);

    const userInfoOldBefore = await p.premiaFeeDiscount.userInfo(user1.address);
    expect(userInfoOldBefore.stakePeriod).to.not.eq(0);
    expect(userInfoOldBefore.lockedUntil).to.not.eq(0);
    expect(userInfoOldBefore.balance).to.not.eq(0);

    await p.premiaFeeDiscount.connect(user1).migrateStake();

    const userInfoOldAfter = await p.premiaFeeDiscount.userInfo(user1.address);
    const userInfoNew = await newContract.userInfo(user1.address);

    expect(userInfoOldAfter.stakePeriod).to.eq(0);
    expect(userInfoOldAfter.lockedUntil).to.eq(0);
    expect(userInfoOldAfter.balance).to.eq(0);

    expect(userInfoNew.stakePeriod).to.eq(userInfoOldBefore.stakePeriod);
    expect(userInfoNew.lockedUntil).to.eq(userInfoOldBefore.lockedUntil);
    expect(userInfoNew.balance).to.eq(userInfoOldBefore.balance);
  });
});
