import { expect } from 'chai';
import {
  PremiaBondingCurve,
  TestPremiaBondingCurveUpgrade,
  TestPremiaBondingCurveUpgrade__factory,
} from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getEthBalance, resetHardhat, setTimestamp } from './utils/evm';
import { signERC2612Permit } from './eth-permit/eth-permit';
import { deployContracts, IPremiaContracts } from '../scripts/deployContracts';
import { parseEther } from 'ethers/lib/utils';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
let testPremiaBondingCurveUpgrade: TestPremiaBondingCurveUpgrade;

describe('PremiaBondingCurve', () => {
  beforeEach(async () => {
    await resetHardhat();
    [admin, user1, treasury] = await ethers.getSigners();

    p = await deployContracts(admin, treasury, true);
    testPremiaBondingCurveUpgrade = await new TestPremiaBondingCurveUpgrade__factory(
      admin,
    ).deploy();

    await p.premia.mint(p.premiaBondingCurve.address, parseEther('10000000'));
  });

  it('should require 52k eth to purchase all premia from the bonding curve', async () => {
    expect(
      await p.premiaBondingCurve.getEthCost(0, parseEther('10000000')), // 10m premia
    ).to.eq(parseEther('52000'));
  });

  it('should successfully buyExactTokenAmount 100k premia', async () => {
    const premiaAmount = parseEther('100000');
    const ethAmount = await p.premiaBondingCurve.getEthCost(0, premiaAmount);
    await p.premiaBondingCurve
      .connect(user1)
      .buyExactTokenAmount(premiaAmount, { value: ethAmount });
    expect(await p.premia.balanceOf(user1.address)).to.eq(premiaAmount);
  });

  it('should fail buyExactTokenAmount if not enough eth', async () => {
    const premiaAmount = parseEther('100000');
    const ethAmount = await p.premiaBondingCurve.getEthCost(0, premiaAmount);
    await expect(
      p.premiaBondingCurve.connect(user1).buyExactTokenAmount(premiaAmount, {
        value: ethAmount.sub(1),
      }),
    ).to.be.revertedWith('Value is too small');
  });

  it('should sell successfully and send 10% fee to treasury', async () => {
    const initialEthTreasury = await getEthBalance(treasury.address);

    const premiaAmount = parseEther('100000');
    const ethAmount = await p.premiaBondingCurve.getEthCost(0, premiaAmount);
    await p.premiaBondingCurve
      .connect(user1)
      .buyExactTokenAmount(premiaAmount, {
        value: ethAmount,
      });

    await p.premia
      .connect(user1)
      .approve(p.premiaBondingCurve.address, premiaAmount);
    await p.premiaBondingCurve.connect(user1).sell(premiaAmount, 0);

    const ethTreasury = await getEthBalance(treasury.address);

    expect(ethTreasury.sub(initialEthTreasury)).to.eq(ethAmount.div(10));
    expect(await p.premia.balanceOf(p.premiaBondingCurve.address)).to.eq(
      parseEther('10000000'),
    );
    expect(await getEthBalance(p.premiaBondingCurve.address)).to.eq(0);
  });

  it('should sell successfully with permit', async () => {
    const initialEthTreasury = await getEthBalance(treasury.address);

    const premiaAmount = parseEther('100000');
    const ethAmount = await p.premiaBondingCurve.getEthCost(0, premiaAmount);
    await p.premiaBondingCurve
      .connect(user1)
      .buyExactTokenAmount(premiaAmount, {
        value: ethAmount,
      });

    await p.premia
      .connect(user1)
      .approve(p.premiaBondingCurve.address, premiaAmount);

    const deadline = Math.floor(new Date().getTime() / 1000 + 3600);

    const result = await signERC2612Permit(
      user1.provider,
      p.premia.address,
      user1.address,
      p.premiaBondingCurve.address,
      premiaAmount.toString(),
      deadline,
    );

    await p.premiaBondingCurve
      .connect(user1)
      .sellWithPermit(premiaAmount, 0, deadline, result.v, result.r, result.s);

    const ethTreasury = await getEthBalance(treasury.address);

    expect(ethTreasury.sub(initialEthTreasury)).to.eq(ethAmount.div(10));
    expect(await p.premia.balanceOf(p.premiaBondingCurve.address)).to.eq(
      parseEther('10000000'),
    );
    expect(await getEthBalance(p.premiaBondingCurve.address)).to.eq(0);
  });

  it('should fail selling with permit if permit is invalid', async () => {
    const premiaAmount = parseEther('100000');
    const ethAmount = await p.premiaBondingCurve.getEthCost(0, premiaAmount);
    await p.premiaBondingCurve
      .connect(user1)
      .buyExactTokenAmount(premiaAmount, {
        value: ethAmount,
      });

    await p.premia
      .connect(user1)
      .approve(p.premiaBondingCurve.address, premiaAmount);

    const deadline = Math.floor(new Date().getTime() / 1000 + 3600);

    const result = await signERC2612Permit(
      user1.provider,
      p.premia.address,
      user1.address,
      p.premiaBondingCurve.address,
      premiaAmount.toString(),
      deadline,
    );

    await expect(
      p.premiaBondingCurve
        .connect(user1)
        .sellWithPermit(
          premiaAmount,
          0,
          deadline + 3600,
          result.v,
          result.r,
          result.s,
        ),
    ).to.be.revertedWith('ERC20Permit: invalid signature');
  });

  it('should only allow performing upgrade after 7 days timelock', async () => {
    const premiaAmount = parseEther('1000000');
    const ethAmount = await p.premiaBondingCurve.getEthCost(0, premiaAmount);
    await p.premiaBondingCurve
      .connect(user1)
      .buyExactTokenAmount(premiaAmount, {
        value: ethAmount,
      });

    await p.premiaBondingCurve.startUpgrade(
      testPremiaBondingCurveUpgrade.address,
    );
    await expect(p.premiaBondingCurve.doUpgrade()).to.be.revertedWith(
      'Upgrade still timelocked',
    );

    const now = Math.floor(new Date().getTime() / 1000);

    await setTimestamp(now + 6 * 24 * 3600);

    await expect(p.premiaBondingCurve.doUpgrade()).to.be.revertedWith(
      'Upgrade still timelocked',
    );

    await setTimestamp(now + 7 * 24 * 3600 + 100);

    await p.premiaBondingCurve.doUpgrade();
    expect(await p.premia.balanceOf(p.premiaBondingCurve.address)).to.eq(0);
    expect(
      await p.premia.balanceOf(testPremiaBondingCurveUpgrade.address),
    ).to.eq(parseEther('9000000'));
    expect(await getEthBalance(p.premiaBondingCurve.address)).to.eq(0);
    expect(await getEthBalance(testPremiaBondingCurveUpgrade.address)).to.eq(
      ethAmount,
    );
    expect(await p.premiaBondingCurve.isUpgradeDone()).to.be.true;
  });

  it('should successfully cancel a pending upgrade', async () => {
    await p.premiaBondingCurve.startUpgrade(
      testPremiaBondingCurveUpgrade.address,
    );

    expect(await p.premiaBondingCurve.newContract()).to.eq(
      testPremiaBondingCurveUpgrade.address,
    );
    expect(await p.premiaBondingCurve.upgradeETA()).to.not.eq(0);

    await p.premiaBondingCurve.cancelUpgrade();

    expect(await p.premiaBondingCurve.newContract()).to.not.eq(
      testPremiaBondingCurveUpgrade.address,
    );
    expect(await p.premiaBondingCurve.upgradeETA()).to.eq(0);
    expect(await p.premiaBondingCurve.isUpgradeDone()).to.be.false;
  });

  it('should buyTokenWithExactEthAmount successfully', async () => {
    const tokenAmount = await p.premiaBondingCurve.getTokensPurchasable(
      parseEther('100'),
    );
    await p.premiaBondingCurve
      .connect(user1)
      .buyTokenWithExactEthAmount(0, user1.address, {
        value: parseEther('100'),
      });
    expect(await p.premia.balanceOf(user1.address)).to.eq(tokenAmount);
    expect(await getEthBalance(p.premiaBondingCurve.address)).to.eq(
      parseEther('100'),
    );
  });

  it('should calculate correctly tokens purchasable', async () => {
    const premiaAmount = parseEther('1000000');

    let ethAmount = await p.premiaBondingCurve.getEthCost(0, premiaAmount);
    let tokensPurchasable = await p.premiaBondingCurve.getTokensPurchasable(
      ethAmount,
    );

    expect(tokensPurchasable).to.eq(premiaAmount);

    ethAmount = await p.premiaBondingCurve.getEthCost(0, parseEther('2000000'));
    await p.premiaBondingCurve.buyExactTokenAmount(parseEther('2000000'), {
      value: ethAmount,
    });

    ethAmount = await p.premiaBondingCurve.getEthCost(
      parseEther('2000000'),
      parseEther('5500000'),
    );
    tokensPurchasable = await p.premiaBondingCurve.getTokensPurchasable(
      ethAmount,
    );

    expect(tokensPurchasable).to.eq(parseEther('3500000'));
  });
});
