import { expect } from 'chai';
import {
  PremiaFeeDiscount,
  PremiaFeeDiscount__factory,
  PremiaStaking,
  PremiaStaking__factory,
  TestErc20,
  TestErc20__factory,
} from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let premia: TestErc20;
let xPremia: PremiaStaking;
let premiaFeeDiscount: PremiaFeeDiscount;

describe('PremiaFeeDiscount', () => {
  beforeEach(async () => {
    [admin, user1] = await ethers.getSigners();

    const premiaFactory = new TestErc20__factory(admin);
    const xPremiaFactory = new PremiaStaking__factory(admin);
    const premiaFeeDiscountFactory = new PremiaFeeDiscount__factory(admin);

    premia = await premiaFactory.deploy();
    xPremia = await xPremiaFactory.deploy(premia.address);
    premiaFeeDiscount = await premiaFeeDiscountFactory.deploy(xPremia.address);

    await premiaFeeDiscount.setStakeLevels([
      { amount: ethers.utils.parseEther('5000'), discount: 9000 }, // 90% of fee (= -10%)
      { amount: ethers.utils.parseEther('50000'), discount: 7500 }, // 75% of fee (= -25%)
      { amount: ethers.utils.parseEther('250000'), discount: 2500 }, // 25% of fee (= -75%)
      { amount: ethers.utils.parseEther('500000'), discount: 1000 }, // 10% of fee (= -90%)
    ]);

    await premiaFeeDiscount.setStakePeriod(30 * 24 * 3600, 1e4);
    await premiaFeeDiscount.setStakePeriod(60 * 24 * 3600, 15e3);
    await premiaFeeDiscount.setStakePeriod(90 * 24 * 3600, 2e4);
  });

  it('should correctly overwrite existing stake levels', async () => {
    await premiaFeeDiscount.setStakeLevels([
      { amount: ethers.utils.parseEther('5000'), discount: 8000 },
      { amount: ethers.utils.parseEther('25000'), discount: 4000 },
      { amount: ethers.utils.parseEther('50000'), discount: 2000 },
    ]);

    const length = await premiaFeeDiscount.stakeLevelsLength();
    expect(length).to.eq(3);

    const level0 = await premiaFeeDiscount.stakeLevels(0);
    const level1 = await premiaFeeDiscount.stakeLevels(1);
    const level2 = await premiaFeeDiscount.stakeLevels(2);

    expect(level0.amount).to.eq(ethers.utils.parseEther('5000'));
    expect(level1.amount).to.eq(ethers.utils.parseEther('25000'));
    expect(level2.amount).to.eq(ethers.utils.parseEther('50000'));

    expect(level0.discount).to.eq(8000);
    expect(level1.discount).to.eq(4000);
    expect(level2.discount).to.eq(2000);
  });
});
