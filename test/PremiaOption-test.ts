import { ethers } from 'hardhat';
import { utils } from 'ethers';
import { expect } from 'chai';
import { ERC20Factory, PremiaOptionFactory } from '../contractsTyped';
import { ERC20 } from '../contractsTyped/ERC20';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { PremiaOption } from '../contractsTyped/PremiaOption';

describe('PremiaOption', function () {
  let eth: ERC20;
  let dai: ERC20;
  let premiaOption: PremiaOption;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  beforeEach(async () => {
    [user1, user2] = await ethers.getSigners();
    const erc20Factory = new ERC20Factory(user1);
    eth = await erc20Factory.deploy('ether', 'ETH');
    dai = await erc20Factory.deploy('dai', 'DAI');

    const premiaOptionFactory = new PremiaOptionFactory(user1);
    premiaOption = await premiaOptionFactory.deploy('dummyURI', dai.address);
  });

  it('Should add eth for trading', async function () {
    await premiaOption.addToken(
      eth.address,
      utils.parseEther('1'),
      utils.parseEther('10'),
    );
    const settings = await premiaOption.tokenSettings(eth.address);
    expect(settings.contractSize.eq(utils.parseEther('1'))).to.true;
    expect(settings.strikePriceIncrement.eq(utils.parseEther('10'))).to.true;
    expect(settings.isDisabled).to.false;
  });
});
