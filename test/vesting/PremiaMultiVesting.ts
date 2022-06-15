import { expect } from 'chai';
import {
  PremiaMultiVesting,
  PremiaMultiVesting__factory,
  ERC20Mock,
  ERC20Mock__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { increaseTimestamp, setTimestamp } from '../utils/evm';
import { parseEther } from 'ethers/lib/utils';
import { bnToNumber } from '../utils/math';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let premia: ERC20Mock;
let premiaMultiVesting: PremiaMultiVesting;

const oneMonth = 3600 * 24 * 30;

describe('PremiaMultiVesting', () => {
  let snapshotId: number;

  before(async () => {
    [admin, user1, user2] = await ethers.getSigners();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
    premiaMultiVesting = await new PremiaMultiVesting__factory(admin).deploy(
      premia.address,
    );

    await premia.mint(admin.address, parseEther('10000'));
    await premia
      .connect(admin)
      .approve(premiaMultiVesting.address, parseEther('10000'));
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  it('should correctly handle vesting for multiple deposits', async () => {
    const { timestamp: now } = await ethers.provider.getBlock('latest');

    await premiaMultiVesting
      .connect(admin)
      .addDeposits(
        [user1.address, user2.address],
        [parseEther('100'), parseEther('200')],
        [oneMonth * 12, oneMonth * 12],
      );
    await setTimestamp(now + oneMonth);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits(
        [user1.address, user2.address],
        [parseEther('100'), parseEther('200')],
        [oneMonth * 12, oneMonth * 12],
      );
    await setTimestamp(now + oneMonth * 2);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('150')], [oneMonth * 12]);

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
      .addDeposits(
        [user1.address, user2.address],
        [parseEther('100'), '0'],
        [oneMonth * 12, oneMonth * 12],
      );
    expect(
      (await premiaMultiVesting.getPendingDeposits(user1.address)).length,
    ).to.eq(1);
    expect(
      (await premiaMultiVesting.getPendingDeposits(user2.address)).length,
    ).to.eq(0);
    expect(await premiaMultiVesting.depositsLength(user1.address)).to.eq(1);
    expect(await premiaMultiVesting.depositsLength(user2.address)).to.eq(0);
  });

  it('should now allow a deposit with ETA < previous deposit ETA', async () => {
    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('100')], [oneMonth * 12]);

    await expect(
      premiaMultiVesting
        .connect(admin)
        .addDeposits([user1.address], [parseEther('100')], [oneMonth * 11]),
    ).to.be.revertedWith('ETA must be > prev deposit ETA');
  });

  it('should successfully cancel vesting of deposits not yet unlocked', async () => {
    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('100')], [oneMonth * 12]);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('200')], [oneMonth * 14]);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('350')], [oneMonth * 16]);

    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('650'),
    );

    await increaseTimestamp(oneMonth * 15);

    let deposits = await premiaMultiVesting.getPendingDeposits(user1.address);
    expect(deposits.length).to.eq(3);
    expect(deposits.map((el) => bnToNumber(el.amount))).to.deep.eq([
      100, 200, 350,
    ]);

    await premiaMultiVesting.connect(admin).cancelVesting(user1.address);

    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('300'),
    );

    deposits = await premiaMultiVesting.getPendingDeposits(user1.address);
    expect(deposits.length).to.eq(2);
    expect(deposits.map((el) => bnToNumber(el.amount))).to.deep.eq([100, 200]);
  });

  it('should still work properly after cancelling vesting', async () => {
    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('100')], [oneMonth * 12]);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('200')], [oneMonth * 14]);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('350')], [oneMonth * 16]);

    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('650'),
    );

    await increaseTimestamp(oneMonth * 15);

    let deposits = await premiaMultiVesting.getPendingDeposits(user1.address);
    expect(deposits.length).to.eq(3);
    expect(deposits.map((el) => bnToNumber(el.amount))).to.deep.eq([
      100, 200, 350,
    ]);

    await premiaMultiVesting.connect(admin).cancelVesting(user1.address);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('100')], [oneMonth * 12]);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('200')], [oneMonth * 14]);

    await premiaMultiVesting
      .connect(admin)
      .addDeposits([user1.address], [parseEther('300')], [oneMonth * 16]);

    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('900'),
    );

    deposits = await premiaMultiVesting.getPendingDeposits(user1.address);
    expect(deposits.length).to.eq(5);
    expect(deposits.map((el) => bnToNumber(el.amount))).to.deep.eq([
      100, 200, 100, 200, 300,
    ]);

    await increaseTimestamp(oneMonth * 13);

    await premiaMultiVesting.connect(user1).claimDeposits();
    expect(await premia.balanceOf(user1.address)).to.eq(parseEther('400'));
    expect(await premia.balanceOf(premiaMultiVesting.address)).to.eq(
      parseEther('500'),
    );

    deposits = await premiaMultiVesting.getPendingDeposits(user1.address);
    expect(deposits.length).to.eq(2);
    expect(deposits.map((el) => bnToNumber(el.amount))).to.deep.eq([200, 300]);
  });
});
