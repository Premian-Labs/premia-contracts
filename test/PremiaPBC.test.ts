import { expect } from 'chai';
import { PremiaPBC } from '../contractsTyped';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { getEthBalance, mineBlockUntil, resetHardhat } from './utils/evm';
import { BigNumber } from 'ethers';
import { deployContracts, IPremiaContracts } from '../scripts/deployContracts';
import { parseEther } from 'ethers/lib/utils';

let p: IPremiaContracts;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let user3: SignerWithAddress;
let treasury: SignerWithAddress;
const pbcAmount = parseEther('10000000'); // 10m

describe('PremiaPBC', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, user2, user3, treasury] = await ethers.getSigners();

    p = await deployContracts(admin, treasury, true);

    await p.premia.mint(admin.address, pbcAmount);
    await p.premia.increaseAllowance(p.premiaPBC.address, pbcAmount);
    await p.premiaPBC.addPremia(pbcAmount);
  });

  it('should have added premia to the PBC', async () => {
    expect(await p.premiaPBC.premiaTotal()).to.eq(pbcAmount);
    expect(await p.premia.balanceOf(p.premiaPBC.address)).to.eq(pbcAmount);
  });

  it('should deposit successfully', async () => {
    await p.premiaPBC.connect(user1).contribute({ value: parseEther('1') });
    expect(await p.premiaPBC.ethTotal()).to.eq(parseEther('1'));
    expect(await getEthBalance(p.premiaPBC.address)).to.eq(parseEther('1'));
  });

  it('should fail depositing if PBC has ended', async () => {
    await mineBlockUntil(101);
    await expect(
      p.premiaPBC.connect(user1).contribute({ value: parseEther('1') }),
    ).to.be.revertedWith('PBC ended');
  });

  it('should calculate allocations correctly and withdraw successfully', async () => {
    await p.premiaPBC.connect(user1).contribute({ value: parseEther('10') });

    await p.premiaPBC.connect(user2).contribute({ value: parseEther('10') });

    await p.premiaPBC.connect(user2).contribute({ value: parseEther('20') });

    await p.premiaPBC.connect(user3).contribute({ value: parseEther('60') });

    await mineBlockUntil(101);

    await p.premiaPBC.connect(user1).collect();
    await p.premiaPBC.connect(user2).collect();
    await p.premiaPBC.connect(user3).collect();

    expect(await p.premia.balanceOf(user1.address)).to.eq(pbcAmount.div(10));
    expect(await p.premia.balanceOf(user2.address)).to.eq(
      pbcAmount.mul(3).div(10),
    );
    expect(await p.premia.balanceOf(user3.address)).to.eq(
      pbcAmount.mul(6).div(10),
    );
    expect(await p.premia.balanceOf(p.premiaPBC.address)).to.eq(0);
  });

  it('should fail collecting if address already did', async () => {
    await p.premiaPBC.connect(user1).contribute({ value: parseEther('10') });

    await p.premiaPBC.connect(user2).contribute({ value: parseEther('10') });

    await mineBlockUntil(101);

    await p.premiaPBC.connect(user1).collect();
    await expect(p.premiaPBC.connect(user1).collect()).to.be.revertedWith(
      'Address already collected its reward',
    );
  });

  it('should fail collecting if address did not contribute', async () => {
    await p.premiaPBC.connect(user1).contribute({ value: parseEther('10') });

    await mineBlockUntil(101);

    await expect(p.premiaPBC.connect(user2).collect()).to.be.revertedWith(
      'Address did not contribute',
    );
  });

  it('should allow owner to withdraw eth', async () => {
    await p.premiaPBC.connect(user1).contribute({ value: parseEther('1000') });

    const user2Eth = await getEthBalance(user2.address);

    await expect(
      p.premiaPBC.connect(user1).sendEthToTreasury(),
    ).to.be.revertedWith('Ownable: caller is not the owner');
    await p.premiaPBC.connect(admin).sendEthToTreasury();

    expect(await getEthBalance(p.premiaPBC.address)).to.eq(0);
    expect(await getEthBalance(treasury.address)).to.eq(
      user2Eth.add(parseEther('1000')),
    );
  });

  it('should calculate current premia price correctly', async () => {
    await p.premiaPBC.connect(user1).contribute({ value: parseEther('12') });

    expect(await p.premiaPBC.getPremiaPrice()).to.eq(
      BigNumber.from(parseEther('12')).mul(parseEther('1')).div(pbcAmount),
    );

    await p.premiaPBC.connect(user1).contribute({ value: parseEther('28') });

    expect(await p.premiaPBC.getPremiaPrice()).to.eq(
      BigNumber.from(parseEther('40')).mul(parseEther('1')).div(pbcAmount),
    );
  });
});
