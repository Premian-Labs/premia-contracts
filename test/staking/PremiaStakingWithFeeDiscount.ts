import {
  IPremiaFeeDiscountOld,
  IPremiaFeeDiscountOld__factory,
  PremiaErc20,
  PremiaErc20__factory,
  PremiaStaking,
  PremiaStaking__factory,
  PremiaStakingWithFeeDiscount,
  PremiaStakingWithFeeDiscount__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import chai, { expect } from 'chai';
import { ethers, network } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

import chaiAlmost from 'chai-almost';
import { bnToNumber } from '../utils/math';
import { parseEther } from 'ethers/lib/utils';

chai.use(chaiAlmost(0.05));

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;

const ALCHEMY_KEY = process.env.ALCHEMY_KEY;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`;
const blockNumber = 13639700;

let premia: PremiaErc20;
let xPremia: PremiaStakingWithFeeDiscount;
let xPremiaOld: PremiaStaking;
let feeDiscountOld: IPremiaFeeDiscountOld;

describe('PremiaStakingWithFeeDiscount', () => {
  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);

    [admin, user1] = await ethers.getSigners();

    // Impersonate owner
    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: ['0xc22fae86443aeed038a4ed887bba8f5035fd12f0'],
    });

    treasury = await ethers.getSigner(
      '0xc22fae86443aeed038a4ed887bba8f5035fd12f0',
    );

    premia = PremiaErc20__factory.connect(
      '0x6399c842dd2be3de30bf99bc7d1bbf6fa3650e70',
      treasury,
    );

    //
    xPremiaOld = PremiaStaking__factory.connect(
      '0x16f9d564df80376c61ac914205d3fdff7057d610',
      treasury,
    );

    feeDiscountOld = IPremiaFeeDiscountOld__factory.connect(
      '0xf5aae75d1ad6fdd62cce66137f2674c96feda854',
      treasury,
    );

    //

    const xPremiaImpl = await new PremiaStakingWithFeeDiscount__factory(
      treasury,
    ).deploy(
      '0x6399c842dd2be3de30bf99bc7d1bbf6fa3650e70',
      feeDiscountOld.address,
      xPremiaOld.address,
    );
    const xPremiaProxy = await new ProxyUpgradeableOwnable__factory(
      treasury,
    ).deploy(xPremiaImpl.address);

    xPremia = PremiaStakingWithFeeDiscount__factory.connect(
      xPremiaProxy.address,
      treasury,
    );

    await feeDiscountOld.connect(treasury).setNewContract(xPremia.address);
  });

  it('should successfully migrate locked tokens', async () => {
    const staker = await ethers.getSigner(
      '0x6e4be9b794b1432a8b735ef5b3040392a27b4372',
    );

    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [staker.address],
    });

    await feeDiscountOld.connect(staker).migrateStake();
    expect(bnToNumber(await premia.balanceOf(xPremia.address))).to.almost(500);
    expect(bnToNumber(await xPremia.balanceOf(xPremia.address))).to.almost(500);

    const userInfo = await xPremia.getUserInfo(staker.address);
    expect(bnToNumber(userInfo.balance)).to.almost(500);
    expect(userInfo.stakePeriod).to.eq(15552000);
    expect(userInfo.lockedUntil).to.eq(1652794739);
  });

  it('should successfully migrate old xPremia to new xPremia', async () => {
    const staker = await ethers.getSigner(
      '0xb45b74eb35790d20e5f4225b0ac49d5bb074696e',
    );

    await network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [staker.address],
    });

    await premia.connect(treasury).approve(xPremia.address, 1000);
    await xPremia.connect(treasury).deposit(1000);
    await premia.connect(treasury).transfer(xPremia.address, 1000);

    const xPremiaOldAmount = await xPremiaOld.balanceOf(staker.address);
    await xPremiaOld
      .connect(staker)
      .approve(xPremia.address, parseEther('1000000'));
    await xPremia.connect(staker).migrateWithoutLock(xPremiaOldAmount);

    expect(await xPremiaOld.balanceOf(staker.address)).to.eq(0);

    expect(bnToNumber(await xPremia.balanceOf(staker.address))).to.almost(
      117281.23,
    );
    expect(bnToNumber(await premia.balanceOf(xPremia.address))).to.almost(
      234562.46,
    );
  });
});
