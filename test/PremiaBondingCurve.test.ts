import { expect } from 'chai';
import {
  PremiaBondingCurve,
  TestErc20,
  TestPremiaBondingCurveUpgrade,
  TestPremiaBondingCurveUpgrade__factory,
} from '../typechain';
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
let premiaBondingCurve: PremiaBondingCurve;

describe('PremiaBondingCurve', () => {
  beforeEach(async () => {
    await resetHardhat();
    [admin, user1, treasury] = await ethers.getSigners();

    p = await deployContracts(admin, treasury.address, true);
    premiaBondingCurve = p.premiaBondingCurve as PremiaBondingCurve;
    testPremiaBondingCurveUpgrade =
      await new TestPremiaBondingCurveUpgrade__factory(admin).deploy();

    await (p.premia as TestErc20).mint(
      premiaBondingCurve.address,
      parseEther('10000000'),
    );
  });

  it('should require 52k eth to purchase all premia from the bonding curve', async () => {
    expect(
      await premiaBondingCurve.getEthCost(0, parseEther('10000000')), // 10m premia
    ).to.eq(parseEther('52000'));
  });

  it('should successfully buyExactTokenAmount 100k premia', async () => {
    const premiaAmount = parseEther('100000');
    const ethAmount = await premiaBondingCurve.getEthCost(0, premiaAmount);
    await premiaBondingCurve
      .connect(user1)
      .buyExactTokenAmount(premiaAmount, { value: ethAmount });
    expect(await p.premia.balanceOf(user1.address)).to.eq(premiaAmount);
  });

  it('should fail buyExactTokenAmount if not enough eth', async () => {
    const premiaAmount = parseEther('100000');
    const ethAmount = await premiaBondingCurve.getEthCost(0, premiaAmount);
    await expect(
      premiaBondingCurve.connect(user1).buyExactTokenAmount(premiaAmount, {
        value: ethAmount.sub(1),
      }),
    ).to.be.revertedWith('Value is too small');
  });

  it('should sell successfully and send 10% fee to treasury', async () => {
    const initialEthTreasury = await getEthBalance(treasury.address);

    const premiaAmount = parseEther('100000');
    const ethAmount = await premiaBondingCurve.getEthCost(0, premiaAmount);
    await premiaBondingCurve.connect(user1).buyExactTokenAmount(premiaAmount, {
      value: ethAmount,
    });

    await p.premia
      .connect(user1)
      .approve(premiaBondingCurve.address, premiaAmount);
    await premiaBondingCurve.connect(user1).sell(premiaAmount, 0);

    const ethTreasury = await getEthBalance(treasury.address);

    expect(ethTreasury.sub(initialEthTreasury)).to.eq(ethAmount.div(10));
    expect(await p.premia.balanceOf(premiaBondingCurve.address)).to.eq(
      parseEther('10000000'),
    );
    expect(await getEthBalance(premiaBondingCurve.address)).to.eq(0);
  });

  it('should sell successfully with permit', async () => {
    const initialEthTreasury = await getEthBalance(treasury.address);

    const premiaAmount = parseEther('100000');
    const ethAmount = await premiaBondingCurve.getEthCost(0, premiaAmount);
    await premiaBondingCurve.connect(user1).buyExactTokenAmount(premiaAmount, {
      value: ethAmount,
    });

    await p.premia
      .connect(user1)
      .approve(premiaBondingCurve.address, premiaAmount);

    const deadline = Math.floor(new Date().getTime() / 1000 + 3600);

    const result = await signERC2612Permit(
      user1.provider,
      p.premia.address,
      user1.address,
      premiaBondingCurve.address,
      premiaAmount.toString(),
      deadline,
    );

    await premiaBondingCurve
      .connect(user1)
      .sellWithPermit(premiaAmount, 0, deadline, result.v, result.r, result.s);

    const ethTreasury = await getEthBalance(treasury.address);

    expect(ethTreasury.sub(initialEthTreasury)).to.eq(ethAmount.div(10));
    expect(await p.premia.balanceOf(premiaBondingCurve.address)).to.eq(
      parseEther('10000000'),
    );
    expect(await getEthBalance(premiaBondingCurve.address)).to.eq(0);
  });

  it('should fail selling with permit if permit is invalid', async () => {
    const premiaAmount = parseEther('100000');
    const ethAmount = await premiaBondingCurve.getEthCost(0, premiaAmount);
    await premiaBondingCurve.connect(user1).buyExactTokenAmount(premiaAmount, {
      value: ethAmount,
    });

    await p.premia
      .connect(user1)
      .approve(premiaBondingCurve.address, premiaAmount);

    const deadline = Math.floor(new Date().getTime() / 1000 + 3600);

    const result = await signERC2612Permit(
      user1.provider,
      p.premia.address,
      user1.address,
      premiaBondingCurve.address,
      premiaAmount.toString(),
      deadline,
    );

    await expect(
      premiaBondingCurve
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
    const ethAmount = await premiaBondingCurve.getEthCost(0, premiaAmount);
    await premiaBondingCurve.connect(user1).buyExactTokenAmount(premiaAmount, {
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
    expect(await p.premia.balanceOf(premiaBondingCurve.address)).to.eq(0);
    expect(
      await p.premia.balanceOf(testPremiaBondingCurveUpgrade.address),
    ).to.eq(parseEther('9000000'));
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

  it('should buyTokenWithExactEthAmount successfully', async () => {
    const tokenAmount = await premiaBondingCurve.getTokensPurchasable(
      parseEther('100'),
    );
    await premiaBondingCurve
      .connect(user1)
      .buyTokenWithExactEthAmount(0, user1.address, {
        value: parseEther('100'),
      });
    expect(await p.premia.balanceOf(user1.address)).to.eq(tokenAmount);
    expect(await getEthBalance(premiaBondingCurve.address)).to.eq(
      parseEther('100'),
    );
  });

  it('should calculate correctly tokens purchasable', async () => {
    const premiaAmount = parseEther('1000000');

    let ethAmount = await premiaBondingCurve.getEthCost(0, premiaAmount);
    let tokensPurchasable = await premiaBondingCurve.getTokensPurchasable(
      ethAmount,
    );

    expect(tokensPurchasable).to.eq(premiaAmount);

    ethAmount = await premiaBondingCurve.getEthCost(0, parseEther('2000000'));
    await premiaBondingCurve.buyExactTokenAmount(parseEther('2000000'), {
      value: ethAmount,
    });

    ethAmount = await premiaBondingCurve.getEthCost(
      parseEther('2000000'),
      parseEther('5500000'),
    );
    tokensPurchasable = await premiaBondingCurve.getTokensPurchasable(
      ethAmount,
    );

    expect(tokensPurchasable).to.eq(parseEther('3500000'));
  });
});
