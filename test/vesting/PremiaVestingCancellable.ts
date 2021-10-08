import { expect } from 'chai';
import {
  PremiaVestingCancellable,
  PremiaVestingCancellable__factory,
  ERC20Mock,
  ERC20Mock__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { setTimestamp } from '../utils/evm';
import { parseEther } from 'ethers/lib/utils';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let premia: ERC20Mock;
let premiaVestingCancellable: PremiaVestingCancellable;

describe('PremiaVestingCancellable', () => {
  beforeEach(async () => {
    [admin, user1] = await ethers.getSigners();

    const premiaFactory = new ERC20Mock__factory(admin);

    premia = await premiaFactory.deploy('PREMIA', 18);
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
    ).to.be.revertedWith('Ownable: sender must be owner');
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
