import { expect } from 'chai';
import {
  PremiaVesting,
  PremiaVesting__factory,
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
let premiaVesting: PremiaVesting;

describe('PremiaVesting', () => {
  beforeEach(async () => {
    [admin, user1] = await ethers.getSigners();

    const premiaFactory = new ERC20Mock__factory(admin);
    const premiaVestingFactory = new PremiaVesting__factory(admin);

    premia = await premiaFactory.deploy('PREMIA', 18);
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
    await expect(
      premiaVesting.connect(admin).withdraw(),
    ).to.be.revertedWithCustomError(premiaVesting, 'Ownable__NotOwner');
  });
});
