import { expect } from 'chai';
import { ERC20Mock } from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { increaseTimestamp } from '../utils/evm';
import { signERC2612Permit } from 'eth-permit';
import { deployV1, IPremiaContracts } from '../../scripts/utils/deployV1';
import { parseEther } from 'ethers/lib/utils';
import { beforeEach } from 'mocha';
import { ONE_YEAR } from '../pool/PoolUtil';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;

const stakeAmount = parseEther('120000');
const oneMonth = 30 * 24 * 3600;

describe('FeeDiscount', () => {
  let snapshotId: number;

  before(async () => {
    [admin, user1, treasury] = await ethers.getSigners();

    p = await deployV1(
      admin,
      treasury.address,
      ethers.constants.AddressZero,
      true,
    );

    await (p.premia as ERC20Mock).mint(user1.address, stakeAmount);
    await p.premia
      .connect(user1)
      .increaseAllowance(p.vePremia.address, ethers.constants.MaxUint256);
    await p.vePremia
      .connect(user1)
      .increaseAllowance(
        p.feeDiscountStandalone.address,
        ethers.constants.MaxUint256,
      );
    await p.vePremia.connect(user1).deposit(stakeAmount);
  });

  beforeEach(async () => {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async () => {
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  it('should stake and calculate discount successfully', async () => {
    await p.vePremia.connect(user1).stake(stakeAmount, ONE_YEAR);
    let amountWithBonus = await p.vePremia.getStakeAmountWithBonus(
      user1.address,
    );
    expect(amountWithBonus).to.eq(parseEther('150000'));
    expect(await p.vePremia.getDiscount(user1.address)).to.eq(6250);

    await increaseTimestamp(ONE_YEAR + 1);

    await p.vePremia.connect(user1).unstake(parseEther('10000'));

    amountWithBonus = await p.vePremia.getStakeAmountWithBonus(user1.address);

    expect(amountWithBonus).to.eq(parseEther('137500'));
    expect(await p.vePremia.getDiscount(user1.address)).to.eq(6093);
  });

  it('should stake successfully with permit', async () => {
    await p.vePremia
      .connect(user1)
      .increaseAllowance(p.vePremia.address, stakeAmount);

    await p.vePremia.connect(user1).approve(p.vePremia.address, 0);

    const { timestamp } = await ethers.provider.getBlock('latest');
    const deadline = timestamp + 3600;

    const result = await signERC2612Permit(
      user1.provider,
      p.vePremia.address,
      user1.address,
      p.vePremia.address,
      stakeAmount.toString(),
      deadline,
    );

    await p.vePremia
      .connect(user1)
      .stakeWithPermit(
        stakeAmount,
        ONE_YEAR,
        deadline,
        result.v,
        result.r,
        result.s,
      );

    const amountWithBonus = await p.vePremia.getStakeAmountWithBonus(
      user1.address,
    );
    expect(amountWithBonus).to.eq(parseEther('150000'));
  });

  it('should fail unstaking if stake is still locked', async () => {
    await p.vePremia.connect(user1).stake(stakeAmount, oneMonth);
    await expect(p.vePremia.connect(user1).unstake(1)).to.be.revertedWith(
      'Stake still locked',
    );
  });

  it('should not allow adding to stake with smaller period than period of stake left', async () => {
    await p.feeDiscountStandalone
      .connect(user1)
      .stake(stakeAmount.div(2), 3 * oneMonth);

    await increaseTimestamp(oneMonth);

    // Fail setting one month stake
    await expect(
      p.feeDiscountStandalone
        .connect(user1)
        .stake(stakeAmount.div(4), oneMonth),
    ).to.be.revertedWith('Cannot add stake with lower stake period');

    // Success adding 3 months stake
    await p.feeDiscountStandalone
      .connect(user1)
      .stake(stakeAmount.div(4), 3 * oneMonth);
    let userInfo = await p.feeDiscountStandalone.getUserInfo(user1.address);
    expect(userInfo.balance).to.eq(stakeAmount.div(4).mul(3));
    expect(userInfo.stakePeriod).to.eq(3 * oneMonth);

    // Success adding for 6 months stake
    await p.feeDiscountStandalone
      .connect(user1)
      .stake(stakeAmount.div(4), 6 * oneMonth);
    userInfo = await p.feeDiscountStandalone.getUserInfo(user1.address);
    expect(userInfo.balance).to.eq(stakeAmount);
    expect(userInfo.stakePeriod).to.eq(6 * oneMonth);
  });

  it('should correctly calculate stake period multiplier', async () => {
    expect(await p.feeDiscountStandalone.getStakePeriodMultiplier(0)).to.eq(
      2500,
    );
    expect(
      await p.feeDiscountStandalone.getStakePeriodMultiplier(ONE_YEAR / 2),
    ).to.eq(7500);
    expect(
      await p.feeDiscountStandalone.getStakePeriodMultiplier(ONE_YEAR),
    ).to.eq(12500);
    expect(
      await p.feeDiscountStandalone.getStakePeriodMultiplier(2 * ONE_YEAR),
    ).to.eq(22500);
    expect(
      await p.feeDiscountStandalone.getStakePeriodMultiplier(4 * ONE_YEAR),
    ).to.eq(42500);
    expect(
      await p.feeDiscountStandalone.getStakePeriodMultiplier(5 * ONE_YEAR),
    ).to.eq(42500);
  });
});
