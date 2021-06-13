import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  TradingCompetitionERC20,
  TradingCompetitionERC20__factory,
  TradingCompetitionFactory,
  TradingCompetitionFactory__factory,
} from '../../typechain';
import { ZERO_ADDRESS } from '../utils/constants';

describe('TradingCompetitionFactory', () => {
  let owner: SignerWithAddress;
  let minter: SignerWithAddress;
  let whitelisted: SignerWithAddress;
  let notWhitelisted: SignerWithAddress;

  let factory: TradingCompetitionFactory;
  let token: TradingCompetitionERC20;

  beforeEach(async () => {
    [owner, minter, whitelisted, notWhitelisted] = await ethers.getSigners();
    factory = await new TradingCompetitionFactory__factory(owner).deploy();
    const tokenAddr = await factory.callStatic.deployToken('TEST');
    await factory.deployToken('TEST');
    token = TradingCompetitionERC20__factory.connect(tokenAddr, owner);

    await factory.addWhitelisted([whitelisted.address]);
    await factory.addMinters([minter.address]);
  });

  it('should only allow minter to mint', async () => {
    expect(await factory.isMinter(notWhitelisted.address)).to.eq(false);
    expect(await factory.isMinter(minter.address)).to.eq(true);

    await expect(
      token.connect(whitelisted).mint(notWhitelisted.address, 100),
    ).to.be.revertedWith('Not minter');

    expect(await token.balanceOf(notWhitelisted.address)).to.eq(0);
    await token.connect(minter).mint(notWhitelisted.address, 100);
    expect(await token.balanceOf(notWhitelisted.address)).to.eq(100);
  });

  it('should only allow whitelisted to send/receive tokens', async () => {
    expect(
      await factory.isWhitelisted(ZERO_ADDRESS, notWhitelisted.address),
    ).to.eq(true);
    expect(
      await factory.isWhitelisted(minter.address, notWhitelisted.address),
    ).to.eq(false);
    expect(
      await factory.isWhitelisted(minter.address, whitelisted.address),
    ).to.eq(true);
    expect(
      await factory.isWhitelisted(whitelisted.address, notWhitelisted.address),
    ).to.eq(true);

    await token.connect(minter).mint(notWhitelisted.address, 100);

    await expect(
      token.connect(notWhitelisted).transfer(minter.address, 20),
    ).to.be.revertedWith('Not whitelisted');

    expect(await token.balanceOf(whitelisted.address)).to.eq(0);
    await token.connect(notWhitelisted).transfer(whitelisted.address, 20);
    expect(await token.balanceOf(whitelisted.address)).to.eq(20);
    await token.connect(whitelisted).transfer(minter.address, 10);
    expect(await token.balanceOf(minter.address)).to.eq(10);
  });
});
