import chai, { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  TradingCompetitionERC20,
  TradingCompetitionERC20__factory,
  TradingCompetitionFactory,
  TradingCompetitionFactory__factory,
} from '../../typechain';
import { ZERO_ADDRESS } from '../utils/constants';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import chaiAlmost from 'chai-almost';

chai.use(chaiAlmost(0.01));

describe('TradingCompetitionFactory', () => {
  let owner: SignerWithAddress;
  let minter: SignerWithAddress;
  let whitelisted: SignerWithAddress;
  let blacklisted: SignerWithAddress;
  let notWhitelisted: SignerWithAddress;

  let ethOracle: MockContract;
  let linkOracle: MockContract;

  let factory: TradingCompetitionFactory;
  let ethToken: TradingCompetitionERC20;
  let linkToken: TradingCompetitionERC20;

  const ethPrice = 2000;
  const linkPrice = 20;

  beforeEach(async () => {
    [owner, minter, whitelisted, blacklisted, notWhitelisted] =
      await ethers.getSigners();

    ethOracle = await deployMockContract(owner as any, [
      'function latestAnswer () external view returns (int)',
    ]);

    linkOracle = await deployMockContract(owner as any, [
      'function latestAnswer () external view returns (int)',
    ]);

    await ethOracle.mock.latestAnswer.returns(
      parseUnits(ethPrice.toString(), 8),
    );
    await linkOracle.mock.latestAnswer.returns(
      parseUnits(linkPrice.toString(), 8),
    );

    factory = await new TradingCompetitionFactory__factory(owner).deploy();

    const ethTokenAddr = await factory.callStatic.deployToken(
      'WETH',
      ethOracle.address,
    );
    await factory.deployToken('WETH', ethOracle.address);
    ethToken = TradingCompetitionERC20__factory.connect(ethTokenAddr, owner);

    const linkTokenAddr = await factory.callStatic.deployToken(
      'LINK',
      linkOracle.address,
    );
    await factory.deployToken('LINK', linkOracle.address);
    linkToken = TradingCompetitionERC20__factory.connect(linkTokenAddr, owner);

    await factory.addWhitelisted([whitelisted.address]);
    await factory.addBlacklisted([blacklisted.address]);
    await factory.addMinters([minter.address]);
  });

  it('should only allow minter to mint', async () => {
    expect(await factory.isMinter(notWhitelisted.address)).to.eq(false);
    expect(await factory.isMinter(minter.address)).to.eq(true);

    await expect(
      ethToken.connect(whitelisted).mint(notWhitelisted.address, 100),
    ).to.be.revertedWith('Not minter');

    expect(await ethToken.balanceOf(notWhitelisted.address)).to.eq(0);
    await ethToken.connect(minter).mint(notWhitelisted.address, 100);
    expect(await ethToken.balanceOf(notWhitelisted.address)).to.eq(100);
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

    await ethToken.connect(minter).mint(notWhitelisted.address, 100);

    await expect(
      ethToken.connect(notWhitelisted).transfer(minter.address, 20),
    ).to.be.revertedWith('Not whitelisted');

    expect(await ethToken.balanceOf(whitelisted.address)).to.eq(0);
    await ethToken.connect(notWhitelisted).transfer(whitelisted.address, 20);
    expect(await ethToken.balanceOf(whitelisted.address)).to.eq(20);
    await ethToken.connect(whitelisted).transfer(minter.address, 10);
    expect(await ethToken.balanceOf(minter.address)).to.eq(10);
  });

  it('should not allow blacklisted to send/receive tokens', async () => {
    expect(
      await factory.isWhitelisted(ZERO_ADDRESS, blacklisted.address),
    ).to.eq(false);
    expect(
      await factory.isWhitelisted(minter.address, blacklisted.address),
    ).to.eq(false);
    expect(
      await factory.isWhitelisted(blacklisted.address, whitelisted.address),
    ).to.eq(false);
    expect(
      await factory.isWhitelisted(blacklisted.address, notWhitelisted.address),
    ).to.eq(false);

    await ethToken.connect(minter).mint(notWhitelisted.address, 100);

    await expect(
      ethToken.connect(blacklisted).transfer(whitelisted.address, 20),
    ).to.be.revertedWith('Not whitelisted');
  });

  it('should return correct swap quotes', async () => {
    const inAmount = parseEther('1');

    const outAmount = await factory.getAmountOut(
      ethToken.address,
      linkToken.address,
      inAmount,
    );

    expect(outAmount).to.eq(
      parseEther(((ethPrice / linkPrice) * 0.99).toString()),
    );

    expect(
      await factory.getAmountIn(ethToken.address, linkToken.address, outAmount),
    ).to.eq(inAmount);
  });

  it('should correctly swap tokens from', async () => {
    await ethToken
      .connect(minter)
      .mint(notWhitelisted.address, parseEther('1'));
    expect(await ethToken.balanceOf(notWhitelisted.address)).to.eq(
      parseEther('1'),
    );

    await factory
      .connect(notWhitelisted)
      .swapTokenFrom(ethToken.address, linkToken.address, parseEther('1'));
    expect(await ethToken.balanceOf(notWhitelisted.address)).to.eq(0);
    expect(await linkToken.balanceOf(notWhitelisted.address)).to.eq(
      parseEther('99'),
    );

    await factory
      .connect(notWhitelisted)
      .swapTokenFrom(linkToken.address, ethToken.address, parseEther('50'));
    expect(await ethToken.balanceOf(notWhitelisted.address)).to.eq(
      parseEther('0.495'),
    );
    expect(await linkToken.balanceOf(notWhitelisted.address)).to.eq(
      parseEther('49'),
    );
  });

  it('should correctly swap tokens to', async () => {
    await ethToken
      .connect(minter)
      .mint(notWhitelisted.address, parseEther('1'));
    expect(await ethToken.balanceOf(notWhitelisted.address)).to.eq(
      parseEther('1'),
    );

    await factory
      .connect(notWhitelisted)
      .swapTokenTo(ethToken.address, linkToken.address, parseEther('99'));
    expect(await ethToken.balanceOf(notWhitelisted.address)).to.eq(0);
    expect(await linkToken.balanceOf(notWhitelisted.address)).to.almost(
      parseEther('99'),
    );

    await factory
      .connect(notWhitelisted)
      .swapTokenTo(linkToken.address, ethToken.address, parseEther('0.495'));
    expect(await ethToken.balanceOf(notWhitelisted.address)).to.eq(
      parseEther('0.495'),
    );
    expect(await linkToken.balanceOf(notWhitelisted.address)).to.eq(
      parseEther('49'),
    );
  });

  it('should airdrop tokens to users', async () => {
    const users = [owner.address, whitelisted.address, notWhitelisted.address];

    const tokens = [ethToken, linkToken];
    const amounts = [parseEther('5'), parseEther('500')];

    await expect(
      factory.connect(whitelisted).airdrop(
        users,
        tokens.map((el) => el.address),
        amounts,
      ),
    ).to.be.revertedWith('Not minter');

    await factory.connect(minter).airdrop(
      users,
      tokens.map((el) => el.address),
      amounts,
    );

    for (const user of users) {
      let i = 0;
      for (const token of tokens) {
        expect(await token.balanceOf(user)).to.eq(amounts[i]);
        i++;
      }
    }
  });
});
