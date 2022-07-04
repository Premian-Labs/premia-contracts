import { expect } from 'chai';
import {
  ERC20Mock,
  ERC20Mock__factory,
  PremiaStakingMock,
  PremiaStakingMock__factory,
  PremiaStakingProxy__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { signERC2612Permit } from 'eth-permit';
import { increaseTimestamp } from '../utils/evm';
import { parseEther } from 'ethers/lib/utils';
import { bnToNumber } from '../utils/math';
import { beforeEach } from 'mocha';
import { BigNumberish } from 'ethers';
import { ONE_YEAR } from '../pool/PoolUtil';

let admin: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;
let carol: SignerWithAddress;
let premia: ERC20Mock;
let usdc: ERC20Mock;
let premiaStakingImplementation: PremiaStakingMock;
let premiaStaking: PremiaStakingMock;
let otherPremiaStaking: PremiaStakingMock;

const ONE_DAY = 3600 * 24;

async function bridge(
  premiaStaking: PremiaStakingMock,
  otherPremiaStaking: PremiaStakingMock,
  user: SignerWithAddress,
  amount: BigNumberish,
) {
  // Mocked bridge out
  await premiaStaking
    .connect(alice)
    .sendFrom(
      user.address,
      0,
      user.address,
      amount,
      user.address,
      ethers.constants.AddressZero,
      '0x',
    );

  // Mocked bridge in
  await otherPremiaStaking.creditTo(user.address, amount);
}

describe('PremiaStaking', () => {
  let snapshotId: number;

  before(async () => {
    [admin, alice, bob, carol] = await ethers.getSigners();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
    usdc = await new ERC20Mock__factory(admin).deploy('USDC', 6);
    premiaStakingImplementation = await new PremiaStakingMock__factory(
      admin,
    ).deploy(ethers.constants.AddressZero, premia.address, usdc.address);

    const premiaStakingProxy = await new PremiaStakingProxy__factory(
      admin,
    ).deploy(premiaStakingImplementation.address);

    const otherPremiaStakingProxy = await new PremiaStakingProxy__factory(
      admin,
    ).deploy(premiaStakingImplementation.address);

    premiaStaking = PremiaStakingMock__factory.connect(
      premiaStakingProxy.address,
      admin,
    );

    otherPremiaStaking = PremiaStakingMock__factory.connect(
      otherPremiaStakingProxy.address,
      admin,
    );

    await premia.mint(admin.address, '1000');
    await premia.mint(alice.address, '100');
    await premia.mint(bob.address, '100');
    await premia.mint(carol.address, '100');

    await premia
      .connect(admin)
      .approve(premiaStaking.address, ethers.constants.MaxUint256);
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  describe('FeeDiscount', () => {
    const stakeAmount = parseEther('120000');
    const oneMonth = 30 * 24 * 3600;

    beforeEach(async () => {
      await premia.mint(alice.address, stakeAmount);
      await premia
        .connect(alice)
        .increaseAllowance(premiaStaking.address, ethers.constants.MaxUint256);
    });

    it('should stake and calculate discount successfully', async () => {
      await premiaStaking.connect(alice).stake(stakeAmount, ONE_YEAR);
      let amountWithBonus = await premiaStaking.getStakeAmountWithBonus(
        alice.address,
      );
      expect(amountWithBonus).to.eq(parseEther('150000'));
      expect(await premiaStaking.getDiscount(alice.address)).to.eq(6250);

      await increaseTimestamp(ONE_YEAR + 1);

      await premiaStaking.connect(alice).startWithdraw(parseEther('10000'));

      amountWithBonus = await premiaStaking.getStakeAmountWithBonus(
        alice.address,
      );

      expect(amountWithBonus).to.eq(parseEther('137500'));
      expect(await premiaStaking.getDiscount(alice.address)).to.eq(6093);
    });

    it('should stake successfully with permit', async () => {
      const { timestamp } = await ethers.provider.getBlock('latest');
      const deadline = timestamp + 3600;

      const result = await signERC2612Permit(
        alice.provider,
        premia.address,
        alice.address,
        premiaStaking.address,
        stakeAmount.toString(),
        deadline,
      );

      await premiaStaking
        .connect(alice)
        .stakeWithPermit(
          stakeAmount,
          ONE_YEAR,
          deadline,
          result.v,
          result.r,
          result.s,
        );

      const amountWithBonus = await premiaStaking.getStakeAmountWithBonus(
        alice.address,
      );
      expect(amountWithBonus).to.eq(parseEther('150000'));
    });

    it('should fail unstaking if stake is still locked', async () => {
      await premiaStaking.connect(alice).stake(stakeAmount, oneMonth);
      await expect(
        premiaStaking.connect(alice).startWithdraw(1),
      ).to.be.revertedWith('Stake still locked');
    });

    it('should not allow adding to stake with smaller period than period of stake left', async () => {
      await premiaStaking
        .connect(alice)
        .stake(stakeAmount.div(2), 3 * oneMonth);

      await increaseTimestamp(oneMonth);

      // Fail setting one month stake
      await expect(
        premiaStaking.connect(alice).stake(stakeAmount.div(4), oneMonth),
      ).to.be.revertedWith('Cannot add stake with lower stake period');

      // Success adding 3 months stake
      await premiaStaking
        .connect(alice)
        .stake(stakeAmount.div(4), 3 * oneMonth);
      let userInfo = await premiaStaking.getUserInfo(alice.address);
      let balance = await premiaStaking.balanceOf(alice.address);
      expect(balance).to.eq(stakeAmount.div(4).mul(3));
      expect(userInfo.stakePeriod).to.eq(3 * oneMonth);

      // Success adding for 6 months stake
      await premiaStaking
        .connect(alice)
        .stake(stakeAmount.div(4), 6 * oneMonth);
      userInfo = await premiaStaking.getUserInfo(alice.address);
      balance = await premiaStaking.balanceOf(alice.address);
      expect(balance).to.eq(stakeAmount);
      expect(userInfo.stakePeriod).to.eq(6 * oneMonth);
    });

    it('should correctly calculate stake period multiplier', async () => {
      expect(await premiaStaking.getStakePeriodMultiplier(0)).to.eq(2500);
      expect(await premiaStaking.getStakePeriodMultiplier(ONE_YEAR / 2)).to.eq(
        7500,
      );
      expect(await premiaStaking.getStakePeriodMultiplier(ONE_YEAR)).to.eq(
        12500,
      );
      expect(await premiaStaking.getStakePeriodMultiplier(2 * ONE_YEAR)).to.eq(
        22500,
      );
      expect(await premiaStaking.getStakePeriodMultiplier(4 * ONE_YEAR)).to.eq(
        42500,
      );
      expect(await premiaStaking.getStakePeriodMultiplier(5 * ONE_YEAR)).to.eq(
        42500,
      );
    });
  });

  it('should successfully stake with permit', async () => {
    const { timestamp } = await ethers.provider.getBlock('latest');
    const deadline = timestamp + 3600;

    const result = await signERC2612Permit(
      alice.provider,
      premia.address,
      alice.address,
      premiaStaking.address,
      '100',
      deadline,
    );

    await premiaStaking
      .connect(alice)
      .stakeWithPermit('100', 0, deadline, result.v, result.r, result.s);
    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(100);
  });

  it('should not allow enter if not enough approve', async () => {
    await expect(
      premiaStaking.connect(alice).stake('100', 0),
    ).to.be.revertedWith('ERC20: transfer amount exceeds allowance');
    await premia.connect(alice).approve(premiaStaking.address, '50');
    await expect(
      premiaStaking.connect(alice).stake('100', 0),
    ).to.be.revertedWith('ERC20: transfer amount exceeds allowance');
    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premiaStaking.connect(alice).stake('100', 0);

    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(100);
  });

  it('should not allow withdraw more than what you have', async () => {
    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premiaStaking.connect(alice).stake('100', 0);

    await expect(
      premiaStaking.connect(alice).startWithdraw('200'),
    ).to.be.revertedWith('ERC20: burn amount exceeds balance');
  });

  it('should correctly handle withdrawal with delay', async () => {
    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premiaStaking.connect(alice).stake('100', 0);

    await expect(premiaStaking.connect(alice).withdraw()).to.be.revertedWith(
      'No pending withdrawal',
    );

    await premiaStaking.connect(alice).startWithdraw('40');

    expect(await premiaStaking.getAvailablePremiaAmount()).to.eq('60');

    await increaseTimestamp(ONE_DAY * 10 - 5);
    await expect(premiaStaking.connect(alice).withdraw()).to.be.revertedWith(
      'Withdrawal still pending',
    );

    await increaseTimestamp(10);

    await premiaStaking.connect(alice).withdraw();
    expect(await premiaStaking.balanceOf(alice.address)).to.eq('60');
    expect(await premia.balanceOf(alice.address)).to.eq('40');

    await expect(premiaStaking.connect(alice).withdraw()).to.be.revertedWith(
      'No pending withdrawal',
    );
  });

  it('should distribute partial rewards properly', async () => {
    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premia.connect(bob).approve(premiaStaking.address, '100');
    await premia.connect(carol).approve(premiaStaking.address, '100');

    // Alice enters and gets 20 shares. Bob enters and gets 10 shares.
    await premiaStaking.connect(alice).stake('30', 0);
    await premiaStaking.connect(bob).stake('10', 0);
    await premiaStaking.connect(carol).stake('10', 0);

    let aliceBalance = await premiaStaking.balanceOf(alice.address);
    let bobBalance = await premiaStaking.balanceOf(bob.address);
    let carolBalance = await premiaStaking.balanceOf(carol.address);
    let contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(30);
    expect(bobBalance).to.eq(10);
    expect(carolBalance).to.eq(10);
    expect(contractBalance).to.eq(50);

    // PremiaStaking get 20 more PREMIAs from an external source.
    await premiaStaking.connect(admin).addRewards('50');

    await premiaStaking.connect(bob).startWithdraw('10');
    expect((await premiaStaking.getPendingWithdrawal(bob.address))[0]).to.eq(
      '10',
    );

    await increaseTimestamp(ONE_DAY * 30);

    await premiaStaking.connect(bob).withdraw();

    await premiaStaking.connect(carol).startWithdraw('10');
    expect((await premiaStaking.getPendingWithdrawal(carol.address))[0]).to.eq(
      '16',
    );
  });

  it('should work with more than one participant', async () => {
    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premia.connect(bob).approve(premiaStaking.address, '100');
    await premia.connect(carol).approve(premiaStaking.address, '100');

    // Alice enters and gets 20 shares. Bob enters and gets 10 shares.
    await premiaStaking.connect(alice).stake('30', 0);
    await premiaStaking.connect(bob).stake('10', 0);
    await premiaStaking.connect(carol).stake('10', 0);

    let aliceBalance = await premiaStaking.balanceOf(alice.address);
    let bobBalance = await premiaStaking.balanceOf(bob.address);
    let carolBalance = await premiaStaking.balanceOf(carol.address);
    let contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(30);
    expect(bobBalance).to.eq(10);
    expect(carolBalance).to.eq(10);
    expect(contractBalance).to.eq(50);

    // PremiaStaking get 20 more PREMIAs from an external source.
    await premiaStaking.connect(admin).addRewards('50');

    await increaseTimestamp(ONE_DAY * 30);

    expect(await premiaStaking.getPendingRewards()).to.eq('26');
    // expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(
    //   parseEther('1.52'),
    // ); // ToDo : Update

    await increaseTimestamp(ONE_DAY * 300000);

    // Bob deposits 50 more PREMIAs. She should receive 50*50/100 = 25 shares.
    await premiaStaking.connect(bob).stake('50', 0);

    // expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(
    //   parseEther('2'),
    // ); // ToDo : Update

    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);
    carolBalance = await premiaStaking.balanceOf(carol.address);

    expect(aliceBalance).to.eq(30);
    expect(bobBalance).to.eq(35);
    expect(carolBalance).to.eq(10);

    await premiaStaking.connect(alice).startWithdraw('5');
    await premiaStaking.connect(bob).startWithdraw('20');

    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);
    carolBalance = await premiaStaking.balanceOf(carol.address);

    expect(aliceBalance).to.eq(25);
    expect(bobBalance).to.eq(15);
    expect(carolBalance).to.eq(10);

    // Pending withdrawals should not count anymore as staked
    await premiaStaking.connect(admin).addRewards('100');

    await increaseTimestamp(ONE_DAY * 30);

    expect(await premiaStaking.getPendingRewards()).to.eq('51');

    await increaseTimestamp(ONE_DAY * 300000);

    // expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(
    //   parseEther('4'),
    // ); // ToDo : Update

    await increaseTimestamp(10 * ONE_DAY + 1);
    await premiaStaking.connect(alice).withdraw();
    await premiaStaking.connect(bob).withdraw();

    let alicePremiaBalance = await premia.balanceOf(alice.address);
    let bobPremiaBalance = await premia.balanceOf(bob.address);

    // Alice = 100 - 30 + (5 * 2)
    expect(alicePremiaBalance).to.eq(80);
    // Bob = 100 - 10 - 50 + 40
    expect(bobPremiaBalance).to.eq(80);

    await premiaStaking.connect(alice).startWithdraw('25');
    await premiaStaking.connect(bob).startWithdraw('15');
    await premiaStaking.connect(carol).startWithdraw('10');

    await increaseTimestamp(10 * ONE_DAY + 1);

    await premiaStaking.connect(alice).withdraw();
    await premiaStaking.connect(bob).withdraw();
    await premiaStaking.connect(carol).withdraw();

    alicePremiaBalance = await premia.balanceOf(alice.address);
    bobPremiaBalance = await premia.balanceOf(bob.address);
    const carolPremiaBalance = await premia.balanceOf(carol.address);

    expect(await premiaStaking.totalSupply()).to.eq(0);
    expect(alicePremiaBalance).to.eq(180);
    expect(bobPremiaBalance).to.eq(140);
    expect(carolPremiaBalance).to.eq(130);
  });

  it('should correctly calculate decay', async () => {
    const oneMonth = 30 * 24 * 3600;
    expect(
      bnToNumber(await premiaStaking.decay(parseEther('100'), 0, oneMonth)),
    ).to.almost(49.66);

    expect(
      bnToNumber(await premiaStaking.decay(parseEther('100'), 0, oneMonth * 2)),
    ).to.almost(24.66);
  });

  it('should correctly bridge to other contract', async () => {
    await premia.connect(alice).approve(premiaStaking.address, '100');

    await premiaStaking.connect(alice).stake('100', 365 * 24 * 3600);
    await premiaStaking.connect(alice).approve(premiaStaking.address, '100');

    expect(await premiaStaking.totalSupply()).to.eq(100);
    expect(await otherPremiaStaking.totalSupply()).to.eq(0);

    await bridge(premiaStaking, otherPremiaStaking, alice, '10');

    expect(await premia.balanceOf(premiaStaking.address)).to.eq(100);
    expect(await premia.balanceOf(otherPremiaStaking.address)).to.eq(0);
    expect(await premiaStaking.totalSupply()).to.eq(90);
    expect(await otherPremiaStaking.totalSupply()).to.eq(10);
  });
});
