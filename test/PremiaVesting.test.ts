import { expect } from 'chai';
import {
  PremiaMultiVesting,
  PremiaMultiVesting__factory,
  PremiaVesting,
  PremiaVesting__factory,
  PremiaVestingCancellable,
  PremiaVestingCancellable__factory,
  TestErc20,
  TestErc20__factory,
} from '../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat, setTimestamp } from './utils/evm';
import { parseEther } from 'ethers/lib/utils';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let premia: TestErc20;
let premiaVesting: PremiaVesting;
let premiaVestingCancellable: PremiaVestingCancellable;
let premiaMultiVesting: PremiaMultiVesting;

const oneMonth = 3600 * 24 * 30;

describe('PremiaVesting', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1] = await ethers.getSigners();

    const premiaFactory = new TestErc20__factory(admin);
    const premiaVestingFactory = new PremiaVesting__factory(admin);

    premia = await premiaFactory.deploy(18);
    premiaVesting = await premiaVestingFactory.deploy(premia.address);

    const amount = parseEther('730');
    await premia.mint(premiaVesting.address, amount);
    await premiaVesting.transferOwnership(user1.address);
  });

  it('should withdraw 200 premia, then 50 premia if withdrawing after 100 days and then after 25 days', async () => {
    let lastWithdraw = await premiaVesting.lastWithdrawalTimestamp();
    // We remove 1s to timestamp, as it will increment when transaction is mined in hardhat network
    await setTimestamp(lastWithdraw.add(100 * 24 * 3600 - 1).toNumber());
    await premiaVesting.connect(user1).withdraw();

    let balance = await premia.balanceOf(user1.address);
    let balanceLeft = await premia.balanceOf(premiaVesting.address);
    expect(balance).to.eq(parseEther('200'));
    expect(balanceLeft).to.eq(parseEther('530'));

    lastWithdraw = await premiaVesting.lastWithdrawalTimestamp();
    await setTimestamp(lastWithdraw.add(25 * 24 * 3600 - 1).toNumber());
    await premiaVesting.connect(user1).withdraw();

    balance = await premia.balanceOf(user1.address);
    balanceLeft = await premia.balanceOf(premiaVesting.address);
    expect(balance).to.eq(parseEther('250'));
    expect(balanceLeft).to.eq(parseEther('480'));
  });

  it('should withdraw all premia if withdrawing after endTimestamp', async () => {
    const end = await premiaVesting.endTimestamp();
    // We remove 1s to timestamp, as it will increment when transaction is mined in hardhat network
    await setTimestamp(end.add(1).toNumber());
    await premiaVesting.connect(user1).withdraw();

    const balance = await premia.balanceOf(user1.address);
    const balanceLeft = await premia.balanceOf(premiaVesting.address);
    expect(balance).to.eq(parseEther('730'));
    expect(balanceLeft).to.eq(0);
  });

  it('should fail to withdraw if not called by owner', async () => {
    await expect(premiaVesting.connect(admin).withdraw()).to.be.revertedWith(
      'Ownable: caller is not the owner',
    );
  });
});

describe('PremiaVestingCancellable', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1] = await ethers.getSigners();

    const premiaFactory = new TestErc20__factory(admin);

    premia = await premiaFactory.deploy(18);
    premiaVestingCancellable = await new PremiaVestingCancellable__factory(
      admin,
    ).deploy(premia.address, admin.address, admin.address);

    const amount = parseEther('730');
    await premia.mint(premiaVestingCancellable.address, amount);
    await premiaVestingCancellable.transferOwnership(user1.address);
  });

  it('should withdraw 100 premia, then 25 premia if withdrawing after 100 days and then after 25 days', async () => {
    let lastWithdraw = await premiaVestingCancellable.lastWithdrawalTimestamp();
    // We remove 1s to timestamp, as it will increment when transaction is mined in hardhat network
    await setTimestamp(lastWithdraw.add(100 * 24 * 3600 - 1).toNumber());
    await premiaVestingCancellable.connect(user1).withdraw();

    let balance = await premia.balanceOf(user1.address);
    let balanceLeft = await premia.balanceOf(premiaVestingCancellable.address);
    expect(balance).to.eq(parseEther('100'));
    expect(balanceLeft).to.eq(parseEther('630'));

    lastWithdraw = await premiaVestingCancellable.lastWithdrawalTimestamp();
    await setTimestamp(lastWithdraw.add(25 * 24 * 3600 - 1).toNumber());
    await premiaVestingCancellable.connect(user1).withdraw();

    balance = await premia.balanceOf(user1.address);
    balanceLeft = await premia.balanceOf(premiaVestingCancellable.address);
    expect(balance).to.eq(parseEther('125'));
    expect(balanceLeft).to.eq(parseEther('605'));
  });

  it('should withdraw all premia if withdrawing after endTimestamp', async () => {
    const end = await premiaVestingCancellable.endTimestamp();
    // We remove 1s to timestamp, as it will increment when transaction is mined in hardhat network
    await setTimestamp(end.add(1).toNumber());
    await premiaVestingCancellable.connect(user1).withdraw();

    const balance = await premia.balanceOf(user1.address);
    const balanceLeft = await premia.balanceOf(
      premiaVestingCancellable.address,
    );
    expect(balance).to.eq(parseEther('730'));
    expect(balanceLeft).to.eq(0);
  });

  it('should fail to withdraw if not called by owner', async () => {
    await expect(
      premiaVestingCancellable.connect(admin).withdraw(),
    ).to.be.revertedWith('Ownable: caller is not the owner');
  });

  it('should fail cancelling the vesting if not called from thirdParty', async () => {
    await expect(
      premiaVestingCancellable.connect(user1).cancel(),
    ).to.be.revertedWith('Not thirdParty');
  });

  it('should fail cancelling the vesting before min release period is reached', async () => {
    let lastWithdraw = await premiaVestingCancellable.lastWithdrawalTimestamp();
    // We remove 1s to timestamp, as it will increment when transaction is mined in hardhat network
    const balanceTreasuryBefore = await premia.balanceOf(admin.address);

    await setTimestamp(lastWithdraw.add(100 * 24 * 3600 - 1).toNumber());
    await expect(
      premiaVestingCancellable.connect(admin).cancel(),
    ).to.be.revertedWith('Min release period not ended');
  });

  it('should successfully cancel the vesting', async () => {
    let lastWithdraw = await premiaVestingCancellable.lastWithdrawalTimestamp();
    // We remove 1s to timestamp, as it will increment when transaction is mined in hardhat network
    const balanceTreasuryBefore = await premia.balanceOf(admin.address);

    await setTimestamp(lastWithdraw.add(181 * 24 * 3600 - 1).toNumber());
    await premiaVestingCancellable.connect(admin).cancel();

    let balance = await premia.balanceOf(user1.address);
    let balanceLeft = await premia.balanceOf(premiaVestingCancellable.address);
    const balanceTreasuryAfter = await premia.balanceOf(admin.address);
    expect(balance).to.eq(parseEther('181'));
    expect(balanceLeft).to.eq(0);
    expect(balanceTreasuryAfter).to.eq(
      balanceTreasuryBefore.add(parseEther('549')),
    );
  });
});

describe('PremiaMultiVesting', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, user2] = await ethers.getSigners();

    premia = await new TestErc20__factory(admin).deploy(18);
    premiaMultiVesting = await new PremiaMultiVesting__factory(admin).deploy(
      premia.address,
    );

    await premia.mint(admin.address, parseEther('10000'));
    await premia
      .connect(admin)
      .approve(premiaMultiVesting.address, parseEther('10000'));
  });

  it('should correctly handle vesting for multiple deposits', async () => {
    const now = Math.floor(new Date().getTime() / 1000);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits(
        [user1.address, user2.address],
        [parseEther('100'), parseEther('200')],
      );
    await setTimestamp(now + oneMonth);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits(
        [user1.address, user2.address],
        [parseEther('100'), parseEther('200')],
      );
    await setTimestamp(now + oneMonth * 2);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('150')]);

    const nbDepositsUser1 = await premiaMultiVesting.depositsLength(
      user1.address,
    );
    const nbDepositsUser2 = await premiaMultiVesting.depositsLength(
      user2.address,
    );
    expect(nbDepositsUser1).to.eq(3);
    expect(nbDepositsUser2).to.eq(2);

    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('750'),
    );

    let pendingDeposits = await premiaMultiVesting.getPendingDeposits(
      user2.address,
    );
    expect(pendingDeposits.length).to.eq(2);

    // User2 try to claim 1 month before end of vesting
    await setTimestamp(now + oneMonth * 11);
    await premiaMultiVesting.connect(user2).claimDeposits();
    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('750'),
    );
    expect(await premia.balanceOf(user2.address)).to.eq(parseEther('0'));

    // User2 claims after first deposit has ended the 1 year vesting
    await setTimestamp(now + oneMonth * 12.5);
    await premiaMultiVesting.connect(user2).claimDeposits();
    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('550'),
    );
    expect(await premia.balanceOf(user2.address)).to.eq(parseEther('200'));
    pendingDeposits = await premiaMultiVesting.getPendingDeposits(
      user2.address,
    );
    expect(pendingDeposits.length).to.eq(1);

    // User2 try to claim again after first deposit has been claimed
    await premiaMultiVesting.connect(user2).claimDeposits();
    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('550'),
    );
    expect(await premia.balanceOf(user2.address)).to.eq(parseEther('200'));
    pendingDeposits = await premiaMultiVesting.getPendingDeposits(
      user2.address,
    );
    expect(pendingDeposits.length).to.eq(1);

    // User3 claims after the two first deposit have ended the 1 year vesting
    await setTimestamp(now + oneMonth * 13.5);
    await premiaMultiVesting.connect(user1).claimDeposits();
    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('350'),
    );
    expect(await premia.balanceOf(user2.address)).to.eq(parseEther('200'));

    // User2 claims after all deposits ended vesting
    await premiaMultiVesting.connect(user2).claimDeposits();
    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('150'),
    );
    expect(await premia.balanceOf(user2.address)).to.eq(parseEther('400'));

    // User3 claims after all deposits ended vesting
    await setTimestamp(now + oneMonth * 14.5);
    await premiaMultiVesting.connect(user1).claimDeposits();
    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('0'),
    );
    expect(await premia.balanceOf(user1.address)).to.eq(parseEther('350'));
  });

  it('should not include a deposit with an amount of 0', async () => {
    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address, user2.address], [parseEther('100'), '0']);
    expect(
      (await premiaMultiVesting.getPendingDeposits(user1.address)).length,
    ).to.eq(1);
    expect(
      (await premiaMultiVesting.getPendingDeposits(user2.address)).length,
    ).to.eq(0);
    expect(await premiaMultiVesting.depositsLength(user1.address)).to.eq(1);
    expect(await premiaMultiVesting.depositsLength(user2.address)).to.eq(0);
  });
});
