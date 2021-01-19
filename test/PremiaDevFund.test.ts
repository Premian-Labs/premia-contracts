import { expect } from 'chai';
import {
  PremiaDevFund,
  PremiaDevFund__factory,
  TestErc20,
  TestErc20__factory,
} from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { resetHardhat, setTimestamp } from './utils/evm';
import { parseEther } from 'ethers/lib/utils';
import { ZERO_ADDRESS } from './utils/constants';

let admin: SignerWithAddress;
let premia: TestErc20;
let premiaDevFund: PremiaDevFund;

describe('PremiaDevFund', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin] = await ethers.getSigners();

    premia = await new TestErc20__factory(admin).deploy();
    premiaDevFund = await new PremiaDevFund__factory(admin).deploy(
      premia.address,
    );

    await premia.mint(premiaDevFund.address, parseEther('3000'));
  });

  it('should not allow withdrawal if timelock has not passed', async () => {
    await expect(premiaDevFund.doWithdraw()).to.be.revertedWith(
      'No pending withdrawal',
    );

    await premiaDevFund.startWithdrawal(admin.address, parseEther('1000'));
    expect(await premiaDevFund.pendingWithdrawalAmount()).to.eq(
      parseEther('1000'),
    );
    expect(await premiaDevFund.pendingWithdrawalDestination()).to.eq(
      admin.address,
    );

    await expect(premiaDevFund.doWithdraw()).to.be.revertedWith(
      'Still timelocked',
    );

    const now = Math.floor(new Date().getTime() / 1000);
    await setTimestamp(now + 3 * 24 * 3600 - 200);

    await expect(premiaDevFund.doWithdraw()).to.be.revertedWith(
      'Still timelocked',
    );

    await setTimestamp(now + 3 * 24 * 3600 + 60);

    await premiaDevFund.doWithdraw();

    expect(await premia.balanceOf(admin.address)).to.eq(parseEther('1000'));
    expect(await premia.balanceOf(premiaDevFund.address)).to.eq(
      parseEther('2000'),
    );

    await expect(premiaDevFund.doWithdraw()).to.be.revertedWith(
      'No pending withdrawal',
    );
    expect(await premiaDevFund.pendingWithdrawalAmount()).to.eq(0);
    expect(await premiaDevFund.pendingWithdrawalDestination()).to.eq(
      ZERO_ADDRESS,
    );
    expect(await premiaDevFund.withdrawalETA()).to.eq(0);
  });
});
