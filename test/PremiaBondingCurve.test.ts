import { expect } from 'chai';
import {
  PremiaBondingCurve,
  PremiaBondingCurve__factory,
  TestErc20,
  TestErc20__factory,
  TestPremiaBondingCurveUpgrade,
  TestPremiaBondingCurveUpgrade__factory,
} from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getEthBalance, resetHardhat, setTimestamp } from './utils/evm';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
let premia: TestErc20;
let premiaBondingCurve: PremiaBondingCurve;
let testPremiaBondingCurveUpgrade: TestPremiaBondingCurveUpgrade;

describe('PremiaBondingCurve', () => {
  beforeEach(async () => {
    await resetHardhat();
    [admin, user1, treasury] = await ethers.getSigners();

    const premiaFactory = new TestErc20__factory(admin);
    const premiaBondingCurveFactory = new PremiaBondingCurve__factory(admin);
    const testPremiaBondingCurveUpgradeFactory = new TestPremiaBondingCurveUpgrade__factory(
      admin,
    );

    premia = await premiaFactory.deploy();
    premiaBondingCurve = await premiaBondingCurveFactory.deploy(
      premia.address,
      treasury.address,
      '200000000000000', // 0.0002 eth
      '1000000000',
    );
    testPremiaBondingCurveUpgrade = await testPremiaBondingCurveUpgradeFactory.deploy();

    await premia.mint(
      premiaBondingCurve.address,
      ethers.utils.parseEther('10000000'),
    );
  });

  it('should require 52k eth to purchase all premia from the bonding curve', async () => {
    expect(
      await premiaBondingCurve.s(0, ethers.utils.parseEther('10000000')), // 10m premia
    ).to.eq(ethers.utils.parseEther('52000'));
  });

  it('should successfully buy 100k premia', async () => {
    const premiaAmount = ethers.utils.parseEther('100000');
    const ethAmount = await premiaBondingCurve.s(0, premiaAmount);
    await premiaBondingCurve
      .connect(user1)
      .buy(premiaAmount, { value: ethAmount });
    expect(await premia.balanceOf(user1.address)).to.eq(premiaAmount);
  });

  it('should fail buying if not enough eth', async () => {
    const premiaAmount = ethers.utils.parseEther('100000');
    const ethAmount = await premiaBondingCurve.s(0, premiaAmount);
    await expect(
      premiaBondingCurve.connect(user1).buy(premiaAmount, {
        value: ethAmount.sub(1),
      }),
    ).to.be.revertedWith('Value is too small');
  });

  it('should sell successfully and send 10% fee to treasury', async () => {
    const initialEthTreasury = await getEthBalance(treasury.address);

    const premiaAmount = ethers.utils.parseEther('100000');
    const ethAmount = await premiaBondingCurve.s(0, premiaAmount);
    await premiaBondingCurve.connect(user1).buy(premiaAmount, {
      value: ethAmount,
    });

    await premia
      .connect(user1)
      .approve(premiaBondingCurve.address, premiaAmount);
    await premiaBondingCurve.connect(user1).sell(premiaAmount);

    const ethTreasury = await getEthBalance(treasury.address);

    expect(ethTreasury.sub(initialEthTreasury)).to.eq(ethAmount.div(10));
    expect(await premia.balanceOf(premiaBondingCurve.address)).to.eq(
      ethers.utils.parseEther('10000000'),
    );
    expect(await getEthBalance(premiaBondingCurve.address)).to.eq(0);
  });

  it('should only allow performing upgrade after 7 days timelock', async () => {
    const premiaAmount = ethers.utils.parseEther('1000000');
    const ethAmount = await premiaBondingCurve.s(0, premiaAmount);
    await premiaBondingCurve.connect(user1).buy(premiaAmount, {
      value: ethAmount,
    });

    await premiaBondingCurve.startUpgrade(
      testPremiaBondingCurveUpgrade.address,
    );
    await expect(premiaBondingCurve.doUpgrade()).to.be.revertedWith(
      'Upgrade still timelocked',
    );

    const now = Math.floor(new Date().getTime() / 1000);

    await setTimestamp(now + 6 * 24 * 3600);

    await expect(premiaBondingCurve.doUpgrade()).to.be.revertedWith(
      'Upgrade still timelocked',
    );

    await setTimestamp(now + 7 * 24 * 3600 + 100);

    await premiaBondingCurve.doUpgrade();
    expect(await premia.balanceOf(premiaBondingCurve.address)).to.eq(0);
    expect(await premia.balanceOf(testPremiaBondingCurveUpgrade.address)).to.eq(
      ethers.utils.parseEther('9000000'),
    );
    expect(await getEthBalance(premiaBondingCurve.address)).to.eq(0);
    expect(await getEthBalance(testPremiaBondingCurveUpgrade.address)).to.eq(
      ethAmount,
    );
    expect(await premiaBondingCurve.isUpgradeDone()).to.be.true;
  });

  it('should successfully cancel a pending upgrade', async () => {
    await premiaBondingCurve.startUpgrade(
      testPremiaBondingCurveUpgrade.address,
    );

    expect(await premiaBondingCurve.newContract()).to.eq(
      testPremiaBondingCurveUpgrade.address,
    );
    expect(await premiaBondingCurve.upgradeETA()).to.not.eq(0);

    await premiaBondingCurve.cancelUpgrade();

    expect(await premiaBondingCurve.newContract()).to.not.eq(
      testPremiaBondingCurveUpgrade.address,
    );
    expect(await premiaBondingCurve.upgradeETA()).to.eq(0);
    expect(await premiaBondingCurve.isUpgradeDone()).to.be.false;
  });
});
