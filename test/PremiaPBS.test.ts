import { expect } from 'chai';
import {
  PremiaBondingCurve,
  PremiaBondingCurve__factory,
  PremiaPBS,
  PremiaPBS__factory,
  TestErc20,
  TestErc20__factory,
} from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getEthBalance, mineBlockUntil, resetHardhat } from './utils/evm';

let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let user3: SignerWithAddress;
let premia: TestErc20;
let premiaPBS: PremiaPBS;
let premiaBondingCurve: PremiaBondingCurve;
const pbsAmount = ethers.utils.parseEther('10000000'); // 10m

describe('PremiaPBS', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, user2, user3] = await ethers.getSigners();

    const premiaFactory = new TestErc20__factory(admin);
    const premiaIBCFactory = new PremiaPBS__factory(admin);
    const premiaBondingCurveFactory = new PremiaBondingCurve__factory(admin);

    premia = await premiaFactory.deploy();
    await premia.mint(admin.address, pbsAmount);
    premiaPBS = await premiaIBCFactory.deploy(premia.address, 0, 100);
    premiaBondingCurve = await premiaBondingCurveFactory.deploy(
      premia.address,
      premiaPBS.address,
    );
    await premiaPBS.setPremiaBondingCurve(premiaBondingCurve.address);

    await premia.increaseAllowance(premiaPBS.address, pbsAmount);
    await premiaPBS.addPremia(pbsAmount);
  });

  it('should have added premia to the PBS', async () => {
    expect(await premiaPBS.premiaTotal()).to.eq(pbsAmount);
    expect(await premia.balanceOf(premiaPBS.address)).to.eq(pbsAmount);
  });

  it('should deposit successfully', async () => {
    await premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('1') });
    expect(await premiaPBS.ethTotal()).to.eq(ethers.utils.parseEther('1'));
    expect(await getEthBalance(premiaPBS.address)).to.eq(
      ethers.utils.parseEther('1'),
    );
  });

  it('should fail depositing if PBS has ended', async () => {
    await mineBlockUntil(101);
    await expect(
      premiaPBS
        .connect(user1)
        .contribute({ value: ethers.utils.parseEther('1') }),
    ).to.be.revertedWith('PBS ended');
  });

  it('should calculate allocations correctly and withdraw successfully', async () => {
    await premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('10') });

    await premiaPBS
      .connect(user2)
      .contribute({ value: ethers.utils.parseEther('10') });

    await premiaPBS
      .connect(user2)
      .contribute({ value: ethers.utils.parseEther('20') });

    await premiaPBS
      .connect(user3)
      .contribute({ value: ethers.utils.parseEther('60') });

    await mineBlockUntil(101);

    await premiaPBS.connect(user1).collect();
    await premiaPBS.connect(user2).collect();
    await premiaPBS.connect(user3).collect();

    expect(await premia.balanceOf(user1.address)).to.eq(pbsAmount.div(10));
    expect(await premia.balanceOf(user2.address)).to.eq(
      pbsAmount.mul(3).div(10),
    );
    expect(await premia.balanceOf(user3.address)).to.eq(
      pbsAmount.mul(6).div(10),
    );
    expect(await premia.balanceOf(premiaPBS.address)).to.eq(0);
  });

  it('should fail collecting if address already did', async () => {
    await premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('10') });

    await premiaPBS
      .connect(user2)
      .contribute({ value: ethers.utils.parseEther('10') });

    await mineBlockUntil(101);

    await premiaPBS.connect(user1).collect();
    await expect(premiaPBS.connect(user1).collect()).to.be.revertedWith(
      'Address already collected its reward',
    );
  });

  it('should fail collecting if address did not contribute', async () => {
    await premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('10') });

    await mineBlockUntil(101);

    await expect(premiaPBS.connect(user2).collect()).to.be.revertedWith(
      'Address did not contribute',
    );
  });

  it('should fail initializing bonding curve if PBS not ended', async () => {
    await expect(premiaPBS.initializeBondingCurve()).to.be.revertedWith(
      'PBS not ended',
    );
  });

  it('should initialize bonding curve', async () => {
    await premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('1000') });

    await mineBlockUntil(101);

    await premiaPBS.initializeBondingCurve();
    expect(await premiaBondingCurve.isInitialized()).to.be.true;
    expect(await premiaBondingCurve.startPrice()).to.eq(
      ethers.utils.parseEther('10000'),
    );
  });

  it('should allow owner to withdraw eth', async () => {
    await premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('1000') });

    const user2Eth = await getEthBalance(user2.address);

    await expect(
      premiaPBS.connect(user1).sendEth(user2.address),
    ).to.be.revertedWith('Ownable: caller is not the owner');
    await premiaPBS.connect(admin).sendEth(user2.address);

    expect(await getEthBalance(premiaPBS.address)).to.eq(0);
    expect(await getEthBalance(user2.address)).to.eq(
      user2Eth.add(ethers.utils.parseEther('1000')),
    );
  });
});
