import { expect } from 'chai';
import {
  PremiaDevFund,
  PremiaDevFund__factory,
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
let premiaDevFund: PremiaDevFund;

describe('PremiaDevFund', () => {
  beforeEach(async () => {
    [admin] = await ethers.getSigners();

    premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
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

    const { timestamp: now } = await ethers.provider.getBlock('latest');

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
