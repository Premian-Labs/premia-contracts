import { expect } from 'chai';
import {
  PremiaWithTimelock,
  PremiaWithTimelock__factory,
  ERC20Mock,
  ERC20Mock__factory,
} from '../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { setTimestamp } from './utils/evm';
import { parseEther } from 'ethers/lib/utils';
import { ZERO_ADDRESS } from './utils/constants';

let admin: SignerWithAddress;
let premia: ERC20Mock;
let premiaWithTimelock: PremiaWithTimelock;

describe('PremiaWithTimelock', () => {
  beforeEach(async () => {
    [admin] = await ethers.getSigners();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
    premiaWithTimelock = await new PremiaWithTimelock__factory(admin).deploy(
      premia.address,
    );

    await premia.mint(premiaWithTimelock.address, parseEther('3000'));
  });

  it('should not allow withdrawal if timelock has not passed', async () => {
    await expect(premiaWithTimelock.doWithdraw()).to.be.revertedWith(
      'No pending withdrawal',
    );

    await premiaWithTimelock.startWithdrawal(admin.address, parseEther('1000'));
    expect(await premiaWithTimelock.pendingWithdrawalAmount()).to.eq(
      parseEther('1000'),
    );
    expect(await premiaWithTimelock.pendingWithdrawalDestination()).to.eq(
      admin.address,
    );

    await expect(premiaWithTimelock.doWithdraw()).to.be.revertedWith(
      'Still timelocked',
    );

    const { timestamp: now } = await ethers.provider.getBlock('latest');

    await setTimestamp(now + 3 * 24 * 3600 - 200);

    await expect(premiaWithTimelock.doWithdraw()).to.be.revertedWith(
      'Still timelocked',
    );

    await setTimestamp(now + 3 * 24 * 3600 + 60);

    await premiaWithTimelock.doWithdraw();

    expect(await premia.balanceOf(admin.address)).to.eq(parseEther('1000'));
    expect(await premia.balanceOf(premiaWithTimelock.address)).to.eq(
      parseEther('2000'),
    );

    await expect(premiaWithTimelock.doWithdraw()).to.be.revertedWith(
      'No pending withdrawal',
    );
    expect(await premiaWithTimelock.pendingWithdrawalAmount()).to.eq(0);
    expect(await premiaWithTimelock.pendingWithdrawalDestination()).to.eq(
      ZERO_ADDRESS,
    );
    expect(await premiaWithTimelock.withdrawalETA()).to.eq(0);
  });
});
