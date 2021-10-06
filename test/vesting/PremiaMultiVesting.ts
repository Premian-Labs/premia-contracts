import { expect } from 'chai';
import {
  PremiaMultiVesting,
  PremiaMultiVesting__factory,
  ERC20Mock,
  ERC20Mock__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { setTimestamp } from '../utils/evm';
import { parseEther } from 'ethers/lib/utils';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let premia: ERC20Mock;
let premiaMultiVesting: PremiaMultiVesting;

const oneMonth = 3600 * 24 * 30;

describe('PremiaMultiVesting', () => {
  beforeEach(async () => {
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

  it('should correctly handle vesting for multiple deposits', async () => {
    const { timestamp: now } = await ethers.provider.getBlock('latest');

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
