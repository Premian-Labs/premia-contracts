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

let admin: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;
let carol: SignerWithAddress;
let premia: ERC20Mock;
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
  const underlyingAmount = await premiaStaking.getUnderlyingAmount(amount);

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
  await otherPremiaStaking.creditTo(user.address, underlyingAmount);
}

describe('PremiaStaking', () => {
  let snapshotId: number;

  before(async () => {
    [admin, alice, bob, carol] = await ethers.getSigners();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
    premiaStakingImplementation = await new PremiaStakingMock__factory(
      admin,
    ).deploy(ethers.constants.AddressZero, premia.address);

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

  it('should successfully enter with permit', async () => {
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
      .depositWithPermit('100', deadline, result.v, result.r, result.s);
    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(100);
  });

  it('should not allow enter if not enough approve', async () => {
    await expect(
      premiaStaking.connect(alice).deposit('100'),
    ).to.be.revertedWith('ERC20: transfer amount exceeds allowance');
    await premia.connect(alice).approve(premiaStaking.address, '50');
    await expect(
      premiaStaking.connect(alice).deposit('100'),
    ).to.be.revertedWith('ERC20: transfer amount exceeds allowance');
    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premiaStaking.connect(alice).deposit('100');

    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(100);
  });

  it('should not allow withdraw more than what you have', async () => {
    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premiaStaking.connect(alice).deposit('100');

    await expect(
      premiaStaking.connect(alice).startWithdraw('200'),
    ).to.be.revertedWith('Not enough underlying available');
  });

  it('should correctly handle withdrawal with delay', async () => {
    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premiaStaking.connect(alice).deposit('100');

    await expect(premiaStaking.connect(alice).withdraw()).to.be.revertedWith(
      'No pending withdrawal',
    );

    await premiaStaking.connect(alice).startWithdraw('40');

    expect(await premiaStaking.getStakedPremiaAmount()).to.eq('60');

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
    await premiaStaking.connect(alice).deposit('30');
    await premiaStaking.connect(bob).deposit('10');
    await premiaStaking.connect(carol).deposit('10');

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
    await premiaStaking.connect(alice).deposit('30');
    await premiaStaking.connect(bob).deposit('10');
    await premiaStaking.connect(carol).deposit('10');

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
    expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(
      parseEther('1.52'),
    );

    await increaseTimestamp(ONE_DAY * 300000);

    // Bob deposits 50 more PREMIAs. She should receive 50*50/100 = 25 shares.
    await premiaStaking.connect(bob).deposit('50');

    expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(
      parseEther('2'),
    );

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

    expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(
      parseEther('4'),
    );

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

    await premiaStaking.connect(alice).deposit('100');
    await premiaStaking.connect(alice).approve(premiaStaking.address, '100');

    await bridge(premiaStaking, otherPremiaStaking, alice, '10');

    expect(await premiaStaking.getDebt()).to.eq(0);
    expect(await premiaStaking.getReserved()).to.eq(10);

    expect(await otherPremiaStaking.getDebt()).to.eq(10);
    expect(await otherPremiaStaking.getReserved()).to.eq(0);

    expect(await premia.balanceOf(premiaStaking.address)).to.eq(100);
    expect(await premia.balanceOf(otherPremiaStaking.address)).to.eq(0);
  });

  it('should correctly normalize underlying with ratio when bridging', async () => {
    await premia.mint(alice.address, '100');

    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premiaStaking.connect(alice).deposit('100');
    await premia.mint(premiaStaking.address, '100');

    await premiaStaking.connect(alice).approve(premiaStaking.address, '100');

    await premia.connect(alice).approve(otherPremiaStaking.address, '100');
    await otherPremiaStaking.connect(alice).deposit('100');
    await premia.mint(otherPremiaStaking.address, '300');

    await premiaStaking
      .connect(alice)
      .approve(otherPremiaStaking.address, '100');

    const ratio1 = await premiaStaking.getXPremiaToPremiaRatio();
    const ratio2 = await otherPremiaStaking.getXPremiaToPremiaRatio();
    const ratio1Nb = bnToNumber(ratio1);
    const ratio2Nb = bnToNumber(ratio2);

    const balance1Before = await premiaStaking.balanceOf(alice.address);
    const balance2Before = await otherPremiaStaking.balanceOf(alice.address);

    await bridge(premiaStaking, otherPremiaStaking, alice, '10');

    const balance1After = await premiaStaking.balanceOf(alice.address);
    const balance2After = await otherPremiaStaking.balanceOf(alice.address);

    expect(await premiaStaking.getXPremiaToPremiaRatio()).to.eq(ratio1);
    expect(await otherPremiaStaking.getXPremiaToPremiaRatio()).to.eq(ratio2);

    expect(balance1Before.sub(balance1After).mul(ratio1Nb)).to.eq(
      balance2After.sub(balance2Before).mul(ratio2Nb),
    );

    const underlying1 = await premiaStaking.getUnderlyingAmount(
      await premiaStaking.totalSupply(),
    );
    const underlying2 = await otherPremiaStaking.getUnderlyingAmount(
      await otherPremiaStaking.totalSupply(),
    );

    expect(underlying1.add(underlying2)).to.eq(600);

    expect(await premiaStaking.balanceOf(alice.address)).to.eq(90);
    expect(await otherPremiaStaking.balanceOf(alice.address)).to.eq(105);
    expect(await premiaStaking.getDebt()).to.eq(0);
    expect(await premiaStaking.getReserved()).to.eq(20);

    expect(await otherPremiaStaking.getDebt()).to.eq(20);
    expect(await otherPremiaStaking.getReserved()).to.eq(0);

    expect(await premia.balanceOf(premiaStaking.address)).to.eq(200);
    expect(await premia.balanceOf(otherPremiaStaking.address)).to.eq(400);
  });
});
