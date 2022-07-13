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
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { bnToNumber } from '../utils/math';
import { beforeEach } from 'mocha';
import { BigNumber, BigNumberish } from 'ethers';
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
const USDC_DECIMALS = 6;

function parseUSDC(amount: string) {
  return parseUnits(amount, USDC_DECIMALS);
}

function decay(
  pendingRewards: number,
  oldTimestamp: number,
  newTimestamp: number,
) {
  return Math.pow(1 - 2.7e-7, newTimestamp - oldTimestamp) * pendingRewards;
}

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
    usdc = await new ERC20Mock__factory(admin).deploy('USDC', USDC_DECIMALS);
    premiaStakingImplementation = await new PremiaStakingMock__factory(
      admin,
    ).deploy(
      ethers.constants.AddressZero,
      premia.address,
      usdc.address,
      ethers.constants.AddressZero,
    );

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

    await usdc.mint(admin.address, parseUSDC('1000'));
    await premia.mint(alice.address, parseEther('100'));
    await premia.mint(bob.address, parseEther('100'));
    await premia.mint(carol.address, parseEther('100'));

    await usdc
      .connect(admin)
      .approve(premiaStaking.address, ethers.constants.MaxUint256);
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  describe('#getTotalVotingPower', () => {
    it('should successfully return total voting power', async () => {
      expect(await premiaStaking.getTotalPower()).to.eq(0);

      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking.connect(alice).stake(parseEther('1'), ONE_DAY * 365);

      expect(await premiaStaking.getTotalPower()).to.eq(parseEther('1.25'));

      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking
        .connect(bob)
        .stake(parseEther('3'), (ONE_DAY * 365) / 2);

      expect(await premiaStaking.getTotalPower()).to.eq(parseEther('3.5'));
    });
  });

  describe('#getUserVotingPower', () => {
    it('should successfully return user voting power', async () => {
      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking.connect(alice).stake(parseEther('1'), ONE_DAY * 365);

      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking
        .connect(bob)
        .stake(parseEther('3'), (ONE_DAY * 365) / 2);

      expect(await premiaStaking.getUserPower(alice.address)).to.eq(
        parseEther('1.25'),
      );
      expect(await premiaStaking.getUserPower(bob.address)).to.eq(
        parseEther('2.25'),
      );
    });
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
      let amountWithBonus = await premiaStaking.getUserPower(alice.address);
      expect(amountWithBonus).to.eq(parseEther('150000'));
      expect(await premiaStaking.getDiscount(alice.address)).to.eq(6250);

      await increaseTimestamp(ONE_YEAR + 1);

      await premiaStaking.connect(alice).startWithdraw(parseEther('10000'));

      amountWithBonus = await premiaStaking.getUserPower(alice.address);

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

      const amountWithBonus = await premiaStaking.getUserPower(alice.address);
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
      parseEther('100').toString(),
      deadline,
    );

    await premiaStaking
      .connect(alice)
      .stakeWithPermit(
        parseEther('100'),
        0,
        deadline,
        result.v,
        result.r,
        result.s,
      );
    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(parseEther('100'));
  });

  it('should not allow enter if not enough approve', async () => {
    await expect(
      premiaStaking.connect(alice).stake(parseEther('100'), 0),
    ).to.be.revertedWith('ERC20: transfer amount exceeds allowance');
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('50'));
    await expect(
      premiaStaking.connect(alice).stake(parseEther('100'), 0),
    ).to.be.revertedWith('ERC20: transfer amount exceeds allowance');
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(parseEther('100'));
  });

  it('should only allow to withdraw what is available', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    await premia
      .connect(bob)
      .approve(otherPremiaStaking.address, parseEther('40'));
    await otherPremiaStaking.connect(bob).stake(parseEther('20'), 0);

    await bridge(premiaStaking, otherPremiaStaking, alice, parseEther('50'));

    await premiaStaking.connect(alice).startWithdraw(parseEther('50'));
    await otherPremiaStaking.connect(alice).startWithdraw(parseEther('10'));
    await otherPremiaStaking.connect(bob).startWithdraw(parseEther('5'));

    await expect(
      otherPremiaStaking.connect(alice).startWithdraw(parseEther('10')),
    ).to.be.revertedWith('Not enough liquidity');
  });

  it('should correctly handle withdrawal with delay', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    await expect(premiaStaking.connect(alice).withdraw()).to.be.revertedWith(
      'No pending withdrawal',
    );

    await premiaStaking.connect(alice).startWithdraw(parseEther('40'));

    expect(await premiaStaking.getAvailablePremiaAmount()).to.eq(
      parseEther('60'),
    );

    await increaseTimestamp(ONE_DAY * 10 - 5);
    await expect(premiaStaking.connect(alice).withdraw()).to.be.revertedWith(
      'Withdrawal still pending',
    );

    await increaseTimestamp(10);

    await premiaStaking.connect(alice).withdraw();
    expect(await premiaStaking.balanceOf(alice.address)).to.eq(
      parseEther('60'),
    );
    expect(await premia.balanceOf(alice.address)).to.eq(parseEther('40'));

    await expect(premiaStaking.connect(alice).withdraw()).to.be.revertedWith(
      'No pending withdrawal',
    );
  });

  it('should distribute partial rewards properly', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premia.connect(bob).approve(premiaStaking.address, parseEther('100'));
    await premia
      .connect(carol)
      .approve(premiaStaking.address, parseEther('100'));

    // Alice enters and gets 20 shares. Bob enters and gets 10 shares.
    await premiaStaking.connect(alice).stake(parseEther('30'), 0);
    await premiaStaking.connect(bob).stake(parseEther('10'), 0);
    await premiaStaking.connect(carol).stake(parseEther('10'), 0);

    let aliceBalance = await premiaStaking.balanceOf(alice.address);
    let bobBalance = await premiaStaking.balanceOf(bob.address);
    let carolBalance = await premiaStaking.balanceOf(carol.address);
    let contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(parseEther('30'));
    expect(bobBalance).to.eq(parseEther('10'));
    expect(carolBalance).to.eq(parseEther('10'));
    expect(contractBalance).to.eq(parseEther('50'));

    // PremiaStaking get 20 more PREMIAs from an external source.
    await premiaStaking.connect(admin).addRewards(parseUSDC('50'));

    await premiaStaking.connect(bob).startWithdraw(parseEther('10'));
    expect((await premiaStaking.getPendingWithdrawal(bob.address))[0]).to.eq(
      parseEther('10'),
    );

    await increaseTimestamp(ONE_DAY * 30);

    await premiaStaking.connect(bob).withdraw();

    await premiaStaking.connect(carol).startWithdraw(parseEther('10'));
    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      parseUSDC('5'),
    );
  });

  it('should work with more than one participant', async () => {
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premia.connect(bob).approve(premiaStaking.address, parseEther('100'));
    await premia
      .connect(carol)
      .approve(premiaStaking.address, parseEther('100'));

    // Alice enters and gets 20 shares. Bob enters and gets 10 shares.
    await premiaStaking.connect(alice).stake(parseEther('30'), 0);
    await premiaStaking.connect(bob).stake(parseEther('10'), 0);
    await premiaStaking.connect(carol).stake(parseEther('10'), 0);

    let aliceBalance = await premiaStaking.balanceOf(alice.address);
    let bobBalance = await premiaStaking.balanceOf(bob.address);
    let carolBalance = await premiaStaking.balanceOf(carol.address);
    let contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(parseEther('30'));
    expect(bobBalance).to.eq(parseEther('10'));
    expect(carolBalance).to.eq(parseEther('10'));
    expect(contractBalance).to.eq(parseEther('50'));

    await premiaStaking.connect(admin).addRewards(parseUSDC('50'));

    let { timestamp } = await ethers.provider.getBlock('latest');

    await increaseTimestamp(ONE_DAY * 30);

    let pendingRewards = await premiaStaking.getPendingRewards();

    let decayValue = BigNumber.from(
      Math.floor(
        decay(50, timestamp, timestamp + ONE_DAY * 30) *
          Math.pow(10, USDC_DECIMALS),
      ),
    );
    expect(pendingRewards).to.eq(parseUSDC('50').sub(decayValue));
    // expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(
    //   parseEther('1.52'),
    // ); // ToDo : Update

    await increaseTimestamp(ONE_DAY * 300000);

    // Bob deposits 50 more PREMIAs. She should receive 50*50/100 = 25 shares.
    await premiaStaking.connect(bob).stake(parseEther('50'), 0);

    // expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(
    //   parseEther('2'),
    // ); // ToDo : Update

    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);
    carolBalance = await premiaStaking.balanceOf(carol.address);

    expect(aliceBalance).to.eq(parseEther('30'));
    expect(bobBalance).to.eq(parseEther('60'));
    expect(carolBalance).to.eq(parseEther('10'));

    await premiaStaking.connect(alice).startWithdraw(parseEther('5'));
    await premiaStaking.connect(bob).startWithdraw(parseEther('20'));

    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);
    carolBalance = await premiaStaking.balanceOf(carol.address);

    expect(aliceBalance).to.eq(parseEther('25'));
    expect(bobBalance).to.eq(parseEther('40'));
    expect(carolBalance).to.eq(parseEther('10'));

    // Pending withdrawals should not count anymore as staked
    await premiaStaking.connect(admin).addRewards(parseUSDC('100'));
    timestamp = (await ethers.provider.getBlock('latest')).timestamp;

    await increaseTimestamp(ONE_DAY * 30);

    pendingRewards = await premiaStaking.getPendingRewards();
    decayValue = BigNumber.from(
      Math.floor(
        decay(100, timestamp, timestamp + ONE_DAY * 30) *
          Math.pow(10, USDC_DECIMALS),
      ),
    );
    expect(pendingRewards).to.eq(parseUSDC('100').sub(decayValue));

    await increaseTimestamp(ONE_DAY * 300000);

    // expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(
    //   parseEther('4'),
    // ); // ToDo : Update

    await increaseTimestamp(10 * ONE_DAY + 1);
    await premiaStaking.connect(alice).withdraw();
    await premiaStaking.connect(bob).withdraw();

    let alicePremiaBalance = await premia.balanceOf(alice.address);
    let bobPremiaBalance = await premia.balanceOf(bob.address);

    // ToDo : Add tests for pending user rewards

    // Alice = 100 - 30 + 5
    expect(alicePremiaBalance).to.eq(parseEther('75'));
    // Bob = 100 - 10 - 50 + 20
    expect(bobPremiaBalance).to.eq(parseEther('60'));

    await premiaStaking.connect(alice).startWithdraw(parseEther('25'));
    await premiaStaking.connect(bob).startWithdraw(parseEther('40'));
    await premiaStaking.connect(carol).startWithdraw(parseEther('10'));

    await increaseTimestamp(10 * ONE_DAY + 1);

    await premiaStaking.connect(alice).withdraw();
    await premiaStaking.connect(bob).withdraw();
    await premiaStaking.connect(carol).withdraw();

    alicePremiaBalance = await premia.balanceOf(alice.address);
    bobPremiaBalance = await premia.balanceOf(bob.address);
    const carolPremiaBalance = await premia.balanceOf(carol.address);

    expect(await premiaStaking.totalSupply()).to.eq(0);
    expect(alicePremiaBalance).to.eq(parseEther('100'));
    expect(bobPremiaBalance).to.eq(parseEther('100'));
    expect(carolPremiaBalance).to.eq(parseEther('100'));

    // ToDo : Add tests for pending user rewards
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
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));

    await premiaStaking
      .connect(alice)
      .stake(parseEther('100'), 365 * 24 * 3600);
    await premiaStaking
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));

    expect(await premiaStaking.totalSupply()).to.eq(parseEther('100'));
    expect(await otherPremiaStaking.totalSupply()).to.eq(0);

    await bridge(premiaStaking, otherPremiaStaking, alice, parseEther('10'));

    expect(await premia.balanceOf(premiaStaking.address)).to.eq(
      parseEther('100'),
    );
    expect(await premia.balanceOf(otherPremiaStaking.address)).to.eq(0);
    expect(await premiaStaking.totalSupply()).to.eq(parseEther('90'));
    expect(await otherPremiaStaking.totalSupply()).to.eq(parseEther('10'));
  });
});
