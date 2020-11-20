import { ethers } from 'hardhat';
import { BigNumberish, utils } from 'ethers';
import { expect } from 'chai';
import { PremiaOptionFactory, TestErc20Factory } from '../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { PremiaOption } from '../contractsTyped/PremiaOption';
import { TestErc20 } from '../contractsTyped/TestErc20';
import exp from 'constants';

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

function getOptionDefaults() {
  return {
    address: eth.address,
    expiration: 1687996800,
    strikePrice: utils.parseEther('10'),
    isCall: true,
    contractAmount: 1,
  };
}

async function addEth() {
  return premiaOption.addToken(
    eth.address,
    utils.parseEther('1'),
    utils.parseEther('10'),
  );
}

async function writeOption(args?: WriteOptionArgs) {
  const defaults = getOptionDefaults();

  return premiaOption.writeOption(
    args?.address ?? defaults.address,
    args?.expiration ?? defaults.expiration,
    args?.strikePrice ?? defaults.strikePrice,
    args?.isCall == undefined ? defaults.isCall : args.isCall,
    args?.contractAmount == undefined
      ? defaults.contractAmount
      : args?.contractAmount,
  );
}

async function addEthAndWriteOptions(contractAmount: number, isCall = true) {
  await addEth();

  if (isCall) {
    await eth.mint(utils.parseEther(contractAmount.toString()));
    await eth.increaseAllowance(
      premiaOption.address,
      utils.parseEther(contractAmount.toString()),
    );
  } else {
    const amount = 10 * contractAmount;
    await dai.mint(utils.parseEther(amount.toString()));
    await dai.increaseAllowance(
      premiaOption.address,
      utils.parseEther(amount.toString()),
    );
  }

  await writeOption({ contractAmount, isCall });
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
      await addEthAndWriteOptions(2);
      const balance = await premiaOption.balanceOf(user1.address, 1);
      expect(balance).to.eq(2);
    });

    it('should be optionId 1', async () => {
      await addEthAndWriteOptions(2);
      const defaults = getOptionDefaults();
      const optionId = await premiaOption.getOptionId(
        eth.address,
        defaults.expiration,
        defaults.strikePrice,
        defaults.isCall,
      );
      expect(optionId).to.eq(1);
    });
  });

  describe('cancelOption', () => {
    it('should successfully cancel 1 call option', async () => {
      await addEthAndWriteOptions(2);

      let optionBalance = await premiaOption.balanceOf(user1.address, 1);
      let ethBalance = await eth.balanceOf(user1.address);

      expect(optionBalance).to.eq(2);
      expect(ethBalance).to.eq(0);

      await premiaOption.cancelOption(1, 1);

      optionBalance = await premiaOption.balanceOf(user1.address, 1);
      ethBalance = await eth.balanceOf(user1.address);

      expect(optionBalance).to.eq(1);
      expect(ethBalance.toString()).to.eq(utils.parseEther('1').toString());
    });

    it('should successfully cancel 1 put option', async () => {
      await addEthAndWriteOptions(2, false);

      let optionBalance = await premiaOption.balanceOf(user1.address, 1);
      let daiBalance = await dai.balanceOf(user1.address);

      expect(optionBalance).to.eq(2);
      expect(daiBalance).to.eq(0);

      await premiaOption.cancelOption(1, 1);

      optionBalance = await premiaOption.balanceOf(user1.address, 1);
      daiBalance = await dai.balanceOf(user1.address);

      expect(optionBalance).to.eq(1);
      expect(daiBalance.toString()).to.eq(utils.parseEther('10').toString());
    });

    it('should fail cancelling option if not a writer', async () => {
      await addEthAndWriteOptions(2);
      await premiaOption.safeTransferFrom(
        user1.address,
        user2.address,
        1,
        1,
        '0x00',
      );
      await expect(
        premiaOption.connect(user2).cancelOption(1, 1),
      ).to.revertedWith('Cant cancel more options than written');
    });

    it('should subtract option written after cancelling', async () => {
      await addEthAndWriteOptions(2);
      await premiaOption.cancelOption(1, 1);
      const nbWritten = await premiaOption.nbWritten(user1.address, 1);
      expect(nbWritten).to.eq(1);
    });
  });

  describe('exerciseOption', () => {
    it('should fail exercising call option if not owned', async () => {
      await addEthAndWriteOptions(2);
      await expect(
        premiaOption.connect(user2).exerciseOption(1, 1),
      ).to.revertedWith('ERC1155: burn amount exceeds balance');
    });

    it('should fail exercising call option if not enough dai', async () => {
      await addEthAndWriteOptions(2);
      await premiaOption.safeTransferFrom(
        user1.address,
        user2.address,
        1,
        1,
        '0x00',
      );
      await expect(
        premiaOption.connect(user2).exerciseOption(1, 1),
      ).to.revertedWith('ERC20: transfer amount exceeds balance');
    });

    it('should successfully exercise 1 call option', async () => {
      await addEthAndWriteOptions(2);
      await premiaOption.safeTransferFrom(
        user1.address,
        user2.address,
        1,
        1,
        '0x00',
      );
      await dai.connect(user2).mint(utils.parseEther('10'));
      await dai
        .connect(user2)
        .increaseAllowance(premiaOption.address, utils.parseEther('10'));
      await premiaOption.connect(user2).exerciseOption(1, 1);

      const nftBalance = await premiaOption.balanceOf(user2.address, 1);
      const daiBalance = await dai.balanceOf(user2.address);
      const ethBalance = await eth.balanceOf(user2.address);

      expect(nftBalance).to.eq(0);
      expect(daiBalance).to.eq(0);
      expect(ethBalance).to.eq(utils.parseEther('1'));
    });

    it('should successfully exercise 1 put option', async () => {
      await addEthAndWriteOptions(2, false);
      await premiaOption.safeTransferFrom(
        user1.address,
        user2.address,
        1,
        1,
        '0x00',
      );
      await eth.connect(user2).mint(utils.parseEther('1'));
      await eth
        .connect(user2)
        .increaseAllowance(premiaOption.address, utils.parseEther('1'));
      await premiaOption.connect(user2).exerciseOption(1, 1);

      const nftBalance = await premiaOption.balanceOf(user2.address, 1);
      const daiBalance = await dai.balanceOf(user2.address);
      const ethBalance = await eth.balanceOf(user2.address);

      expect(nftBalance).to.eq(0);
      expect(daiBalance).to.eq(utils.parseEther('10'));
      expect(ethBalance).to.eq(0);
    });
  });
});
