import { ethers } from 'hardhat';
import { BigNumberish, utils } from 'ethers';
import { expect } from 'chai';
import { PremiaOptionFactory, TestErc20Factory } from '../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { PremiaOption } from '../contractsTyped/PremiaOption';
import { TestErc20 } from '../contractsTyped/TestErc20';

let eth: TestErc20;
let dai: TestErc20;
let premiaOption: PremiaOption;
let user1: SignerWithAddress;
let user2: SignerWithAddress;

interface WriteOptionArgs {
  address?: string;
  expiration?: number;
  strikePrice?: BigNumberish;
  isCall?: boolean;
  contractAmount?: number;
}

async function addEth() {
  return premiaOption.addToken(
    eth.address,
    utils.parseEther('1'),
    utils.parseEther('10'),
  );
}

async function writeOption(args?: WriteOptionArgs) {
  return premiaOption.writeOption(
    args?.address ?? eth.address,
    args?.expiration ?? 1687996800,
    args?.strikePrice ?? utils.parseEther('10'),
    args?.isCall == undefined ? true : args.isCall,
    args?.contractAmount == undefined ? 1 : args?.contractAmount,
  );
}

describe('PremiaOption', function () {
  beforeEach(async () => {
    [user1, user2] = await ethers.getSigners();
    const erc20Factory = new TestErc20Factory(user1);
    eth = await erc20Factory.deploy();
    dai = await erc20Factory.deploy();

    const premiaOptionFactory = new PremiaOptionFactory(user1);
    premiaOption = await premiaOptionFactory.deploy('dummyURI', dai.address);
  });

  it('Should add eth for trading', async function () {
    await addEth();
    const settings = await premiaOption.tokenSettings(eth.address);
    expect(settings.contractSize.eq(utils.parseEther('1'))).to.true;
    expect(settings.strikePriceIncrement.eq(utils.parseEther('10'))).to.true;
    expect(settings.isDisabled).to.false;
  });

  describe('writeOption', () => {
    it('should fail if token not added', async () => {
      await expect(writeOption()).to.be.revertedWith('Token not supported');
    });

    it('should revert if contract amount <= 0', async () => {
      await addEth();
      await expect(writeOption({ contractAmount: 0 })).to.be.revertedWith(
        'Contract amount must be > 0',
      );
    });

    it('should revert if contract strike price <= 0', async () => {
      await addEth();
      await expect(writeOption({ strikePrice: 0 })).to.be.revertedWith(
        'Strike price must be > 0',
      );
    });

    it('should revert if strike price increment is wrong', async () => {
      await addEth();
      await expect(
        writeOption({ strikePrice: utils.parseEther('1') }),
      ).to.be.revertedWith('Wrong strikePrice increment');
    });

    it('should revert if timestamp already passed', async () => {
      await addEth();
      await expect(writeOption({ expiration: 1605858784 })).to.be.revertedWith(
        'Expiration already passed',
      );
    });

    it('should revert if timestamp increment is wrong', async () => {
      await addEth();
      await expect(writeOption({ expiration: 1687996801 })).to.be.revertedWith(
        'Wrong expiration timestamp increment',
      );
    });

    it('should fail if address does not have enough ether for call', async () => {
      await addEth();
      await eth.mint(utils.parseEther('0.99'));
      await eth.increaseAllowance(premiaOption.address, utils.parseEther('1'));
      await expect(writeOption()).to.be.revertedWith(
        'ERC20: transfer amount exceeds balance',
      );
    });

    it('should fail if address does not have enough dai for put', async () => {
      await addEth();
      await dai.mint(utils.parseEther('9.99'));
      await dai.increaseAllowance(premiaOption.address, utils.parseEther('10'));
      await expect(writeOption({ isCall: false })).to.be.revertedWith(
        'ERC20: transfer amount exceeds balance',
      );
    });

    it('should successfully mint 2 options', async () => {
      await addEth();
      await eth.mint(utils.parseEther('2'));
      await eth.increaseAllowance(premiaOption.address, utils.parseEther('2'));
      await writeOption({ contractAmount: 2 });
      const balance = await premiaOption.balanceOf(user1.address, 1);
      expect(balance).to.eq(2);
    });
  });
});
