import { expect } from 'chai';
import { PremiaPBS } from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getEthBalance, mineBlockUntil, resetHardhat } from './utils/evm';
import { BigNumber } from 'ethers';
import { deployContracts, IPremiaContracts } from '../scripts/deployContracts';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let user3: SignerWithAddress;
let treasury: SignerWithAddress;
const pbsAmount = ethers.utils.parseEther('10000000'); // 10m

describe('PremiaPBS', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, user2, user3, treasury] = await ethers.getSigners();

    p = await deployContracts(admin, treasury, true);

    await p.premia.mint(admin.address, pbsAmount);
    await p.premia.increaseAllowance(p.premiaPBS.address, pbsAmount);
    await p.premiaPBS.addPremia(pbsAmount);
  });

  it('should have added premia to the PBS', async () => {
    expect(await p.premiaPBS.premiaTotal()).to.eq(pbsAmount);
    expect(await p.premia.balanceOf(p.premiaPBS.address)).to.eq(pbsAmount);
  });

  it('should deposit successfully', async () => {
    await p.premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('1') });
    expect(await p.premiaPBS.ethTotal()).to.eq(ethers.utils.parseEther('1'));
    expect(await getEthBalance(p.premiaPBS.address)).to.eq(
      ethers.utils.parseEther('1'),
    );
  });

  it('should fail depositing if PBS has ended', async () => {
    await mineBlockUntil(101);
    await expect(
      p.premiaPBS
        .connect(user1)
        .contribute({ value: ethers.utils.parseEther('1') }),
    ).to.be.revertedWith('PBS ended');
  });

  it('should calculate allocations correctly and withdraw successfully', async () => {
    await p.premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('10') });

    await p.premiaPBS
      .connect(user2)
      .contribute({ value: ethers.utils.parseEther('10') });

    await p.premiaPBS
      .connect(user2)
      .contribute({ value: ethers.utils.parseEther('20') });

    await p.premiaPBS
      .connect(user3)
      .contribute({ value: ethers.utils.parseEther('60') });

    await mineBlockUntil(101);

    await p.premiaPBS.connect(user1).collect();
    await p.premiaPBS.connect(user2).collect();
    await p.premiaPBS.connect(user3).collect();

    expect(await p.premia.balanceOf(user1.address)).to.eq(pbsAmount.div(10));
    expect(await p.premia.balanceOf(user2.address)).to.eq(
      pbsAmount.mul(3).div(10),
    );
    expect(await p.premia.balanceOf(user3.address)).to.eq(
      pbsAmount.mul(6).div(10),
    );
    expect(await p.premia.balanceOf(p.premiaPBS.address)).to.eq(0);
  });

  it('should fail collecting if address already did', async () => {
    await p.premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('10') });

    await p.premiaPBS
      .connect(user2)
      .contribute({ value: ethers.utils.parseEther('10') });

    await mineBlockUntil(101);

    await p.premiaPBS.connect(user1).collect();
    await expect(p.premiaPBS.connect(user1).collect()).to.be.revertedWith(
      'Address already collected its reward',
    );
  });

  it('should fail collecting if address did not contribute', async () => {
    await p.premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('10') });

    await mineBlockUntil(101);

    await expect(p.premiaPBS.connect(user2).collect()).to.be.revertedWith(
      'Address did not contribute',
    );
  });

  it('should allow owner to withdraw eth', async () => {
    await p.premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('1000') });

    const user2Eth = await getEthBalance(user2.address);

    await expect(
      p.premiaPBS.connect(user1).sendEthToTreasury(),
    ).to.be.revertedWith('Ownable: caller is not the owner');
    await p.premiaPBS.connect(admin).sendEthToTreasury();

    expect(await getEthBalance(p.premiaPBS.address)).to.eq(0);
    expect(await getEthBalance(treasury.address)).to.eq(
      user2Eth.add(ethers.utils.parseEther('1000')),
    );
  });

  it('should calculate current premia price correctly', async () => {
    await p.premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('12') });

    expect(await p.premiaPBS.getPremiaPrice()).to.eq(
      BigNumber.from(ethers.utils.parseEther('12'))
        .mul(ethers.utils.parseEther('1'))
        .div(pbsAmount),
    );

    await p.premiaPBS
      .connect(user1)
      .contribute({ value: ethers.utils.parseEther('28') });

    expect(await p.premiaPBS.getPremiaPrice()).to.eq(
      BigNumber.from(ethers.utils.parseEther('40'))
        .mul(ethers.utils.parseEther('1'))
        .div(pbsAmount),
    );
  });
});
