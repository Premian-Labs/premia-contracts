import { expect } from 'chai';
import { PremiaFeeDiscount, ERC20Mock } from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { increaseTimestamp } from '../utils/evm';
import { signERC2612Permit } from 'eth-permit';
import { deployV1, IPremiaContracts } from '../../scripts/utils/deployV1';
import { parseEther } from 'ethers/lib/utils';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;

const stakeAmount = parseEther('120000');
const oneMonth = 30 * 24 * 3600;

describe('PremiaFeeDiscount', () => {
  beforeEach(async () => {
    [admin, user1, treasury] = await ethers.getSigners();

    p = await deployV1(admin, treasury.address, true);

    await (p.premia as ERC20Mock).mint(user1.address, stakeAmount);
    await p.premia
      .connect(user1)
      .increaseAllowance(p.xPremia.address, stakeAmount);
    await p.xPremia.connect(user1).deposit(stakeAmount);
  });

  it('should fail staking if stake period does not exists', async () => {
    await expect(
      p.xPremia.connect(user1).stake(stakeAmount, 2 * oneMonth),
    ).to.be.revertedWith('Stake period does not exists');
  });

  it('should stake and calculate discount successfully', async () => {
    await p.xPremia.connect(user1).stake(stakeAmount, 3 * oneMonth);
    let amountWithBonus = await p.xPremia.getStakeAmountWithBonus(
      user1.address,
    );
    expect(amountWithBonus).to.eq(parseEther('150000'));
    expect(await p.xPremia.getDiscount(user1.address)).to.eq(6250);

    await increaseTimestamp(91 * 24 * 3600);

    await p.xPremia.connect(user1).unstake(parseEther('10000'));

    amountWithBonus = await p.xPremia.getStakeAmountWithBonus(user1.address);

    expect(amountWithBonus).to.eq(parseEther('137500'));
    expect(await p.xPremia.getDiscount(user1.address)).to.eq(6093);
  });

  it('should stake successfully with permit', async () => {
    await p.xPremia
      .connect(user1)
      .increaseAllowance(p.feeDiscountStandalone.address, stakeAmount);

    await p.xPremia.connect(user1).approve(p.xPremia.address, 0);

    const { timestamp } = await ethers.provider.getBlock('latest');
    const deadline = timestamp + 3600;

    const result = await signERC2612Permit(
      user1.provider,
      p.xPremia.address,
      user1.address,
      p.feeDiscountStandalone.address,
      stakeAmount.toString(),
      deadline,
    );

    await p.feeDiscountStandalone
      .connect(user1)
      .stakeWithPermit(
        stakeAmount,
        3 * oneMonth,
        deadline,
        result.v,
        result.r,
        result.s,
      );

    const amountWithBonus =
      await p.feeDiscountStandalone.getStakeAmountWithBonus(user1.address);
    expect(amountWithBonus).to.eq(parseEther('150000'));
  });

  it('should fail unstaking if stake is still locked', async () => {
    await p.xPremia.connect(user1).stake(stakeAmount, oneMonth);
    await expect(p.xPremia.connect(user1).unstake(1)).to.be.revertedWith(
      'Stake still locked',
    );
  });

  it('should not allow adding to stake with smaller period than period of stake left', async () => {
    await p.xPremia.connect(user1).stake(stakeAmount.div(2), 3 * oneMonth);

    await increaseTimestamp(oneMonth);

    // Fail setting one month stake
    await expect(
      p.xPremia.connect(user1).stake(stakeAmount.div(4), oneMonth),
    ).to.be.revertedWith('Cannot add stake with lower stake period');

    // Success adding 3 months stake
    await p.xPremia.connect(user1).stake(stakeAmount.div(4), 3 * oneMonth);
    let userInfo = await p.xPremia.getUserInfo(user1.address);
    expect(userInfo.balance).to.eq(stakeAmount.div(4).mul(3));
    expect(userInfo.stakePeriod).to.eq(3 * oneMonth);

    // Success adding for 6 months stake
    await p.xPremia.connect(user1).stake(stakeAmount.div(4), 6 * oneMonth);
    userInfo = await p.xPremia.getUserInfo(user1.address);
    expect(userInfo.balance).to.eq(stakeAmount);
    expect(userInfo.stakePeriod).to.eq(6 * oneMonth);
  });
});
