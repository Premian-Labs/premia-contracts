import { expect } from 'chai';
import {
  ERC20Mock,
  ERC20Mock__factory,
  PremiaVesting,
  PremiaVesting__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { setTimestamp } from '../utils/evm';
import { parseEther } from 'ethers/lib/utils';
import { getCurrentTimestamp } from 'hardhat/internal/hardhat-network/provider/utils/getCurrentTimestamp';
import { ONE_DAY, ONE_YEAR } from '../pool/PoolUtil';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let user3: SignerWithAddress;
let premia: ERC20Mock;
let premiaVesting: PremiaVesting;
const startTimestamp = getCurrentTimestamp() - 10 * ONE_DAY;
const releasePeriod = ONE_YEAR;

describe('PremiaVesting', () => {
  let snapshotId: number;

  before(async () => {
    [admin, user1, user2, user3] = await ethers.getSigners();

    const premiaFactory = new ERC20Mock__factory(admin);
    const premiaVestingFactory = new PremiaVesting__factory(admin);

    premia = await premiaFactory.deploy('PREMIA', 18);
    premiaVesting = await premiaVestingFactory.deploy(
      premia.address,
      startTimestamp,
      releasePeriod,
    );

    const amount = parseEther('730');
    await premia.mint(premiaVesting.address, amount);
    await premiaVesting.transferOwnership(user1.address);
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  it('should properly handle withdrawals', async () => {
    await setTimestamp(startTimestamp + 100 * ONE_DAY);
    expect(await premiaVesting.getAmountAvailableToWithdraw()).to.eq(
      parseEther('200'),
    );
    await premiaVesting
      .connect(user1)
      .withdraw(user1.address, parseEther('150'));

    let balance = await premia.balanceOf(user1.address);
    let balanceLeft = await premia.balanceOf(premiaVesting.address);
    expect(balance).to.eq(parseEther('150'));
    expect(balanceLeft).to.eq(parseEther('580'));
    expect(await premiaVesting.getAmountAvailableToWithdraw()).to.eq(
      '50000023148148148148', // A little above 50, as time increments after tx executed
    );

    await setTimestamp(startTimestamp + 125 * ONE_DAY);
    expect(await premiaVesting.getAmountAvailableToWithdraw()).to.eq(
      '99999999999999999999', // 99.999999999999999999 instead of 100 because of rounding
    );
    await premiaVesting
      .connect(user1)
      .withdraw(user2.address, parseEther('100')); // We can still withdraw 50, cause when this is executed, time is incremented by 1s which brings available slightly above 50

    balance = await premia.balanceOf(user2.address);
    balanceLeft = await premia.balanceOf(premiaVesting.address);
    expect(balance).to.eq(parseEther('100'));
    expect(balanceLeft).to.eq(parseEther('480'));
  });

  it('should be able to withdraw all premia if withdrawing after endTimestamp', async () => {
    await setTimestamp(startTimestamp + 100 * ONE_DAY);
    await premiaVesting
      .connect(user1)
      .withdraw(user1.address, parseEther('200'));

    await setTimestamp(startTimestamp + releasePeriod + 1);
    expect(await premiaVesting.getAmountAvailableToWithdraw()).to.eq(
      parseEther('530'),
    );
    await premiaVesting
      .connect(user1)
      .withdraw(user2.address, parseEther('530'));

    const balance = await premia.balanceOf(user2.address);
    const balanceLeft = await premia.balanceOf(premiaVesting.address);
    expect(balance).to.eq(parseEther('530'));
    expect(balanceLeft).to.eq(0);
  });

  it('should fail to withdraw if not called by owner', async () => {
    await setTimestamp(startTimestamp + 100 * ONE_DAY);
    await expect(
      premiaVesting.connect(admin).withdraw(user1.address, parseEther('100')),
    ).to.be.revertedWithCustomError(premiaVesting, 'Ownable__NotOwner');
  });

  it('should fail to withdraw more than available', async () => {
    await setTimestamp(startTimestamp + 100 * ONE_DAY);

    await expect(
      premiaVesting
        .connect(user1)
        .withdraw(user1.address, parseEther('200.01')),
    ).to.be.revertedWithCustomError(
      premiaVesting,
      'PremiaVesting__InvalidAmount',
    );
  });
});
