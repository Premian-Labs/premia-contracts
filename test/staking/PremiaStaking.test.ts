import { expect } from 'chai';
import {
  PremiaStaking,
  PremiaStaking__factory,
  PremiaStakingProxy__factory,
  ERC20Mock,
  ERC20Mock__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { signERC2612Permit } from 'eth-permit';
import { increaseTimestamp } from '../utils/evm';

let admin: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;
let carol: SignerWithAddress;
let premia: ERC20Mock;
let premiaStakingImplementation: PremiaStaking;
let premiaStaking: PremiaStaking;

const ONE_DAY = 3600 * 24;

describe('PremiaStaking', () => {
  beforeEach(async () => {
    [admin, alice, bob, carol] = await ethers.getSigners();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
    premiaStakingImplementation = await new PremiaStaking__factory(
      admin,
    ).deploy(premia.address);

    const premiaStakingProxy = await new PremiaStakingProxy__factory(
      admin,
    ).deploy(premiaStakingImplementation.address);

    premiaStaking = PremiaStaking__factory.connect(
      premiaStakingProxy.address,
      admin,
    );

    await premia.mint(alice.address, '100');
    await premia.mint(bob.address, '100');
    await premia.mint(carol.address, '100');
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
    ).to.be.revertedWith('ERC20: burn amount exceeds balance');
  });

  it('should work with more than one participant', async () => {
    await premia.connect(alice).approve(premiaStaking.address, '100');
    await premia.connect(bob).approve(premiaStaking.address, '100');

    // Alice enters and gets 20 shares. Bob enters and gets 10 shares.
    await premiaStaking.connect(alice).deposit('20');
    await premiaStaking.connect(bob).deposit('10');

    let aliceBalance = await premiaStaking.balanceOf(alice.address);
    let bobBalance = await premiaStaking.balanceOf(bob.address);
    let contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(20);
    expect(bobBalance).to.eq(10);
    expect(contractBalance).to.eq(30);

    // PremiaStaking get 20 more PREMIAs from an external source.
    await premia.connect(carol).transfer(premiaStaking.address, '20');

    // Alice deposits 10 more PREMIAs. She should receive 10*30/50 = 6 shares.
    await premiaStaking.connect(alice).deposit('10');
    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);

    expect(aliceBalance).to.eq(26);
    expect(bobBalance).to.eq(10);

    // Bob withdraws 5 shares. He should receive 5*60/36 = 8 shares
    await premiaStaking.connect(bob).startWithdraw('5');
    await increaseTimestamp(10 * ONE_DAY + 1);
    await premiaStaking.connect(bob).withdraw();

    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);
    contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(26);
    expect(bobBalance).to.eq(5);
    expect(contractBalance).to.eq(52);

    const alicePremiaBalance = await premia.balanceOf(alice.address);
    const bobPremiaBalance = await premia.balanceOf(bob.address);

    expect(alicePremiaBalance).to.eq(70);
    expect(bobPremiaBalance).to.eq(98);
  });
});
