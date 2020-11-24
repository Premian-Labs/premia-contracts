import { ethers } from 'hardhat';
import { BigNumberish, utils } from 'ethers';
import { expect } from 'chai';
import { TestPremiaOptionFactory, TestErc20Factory } from '../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { TestPremiaOption } from '../contractsTyped/TestPremiaOption';
import { TestErc20 } from '../contractsTyped/TestErc20';

let eth: TestErc20;
let dai: TestErc20;
let premiaOption: TestPremiaOption;
let writer1: SignerWithAddress;
let writer2: SignerWithAddress;
let user1: SignerWithAddress;

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
    expiration: 604800,
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

async function writeOption(user: SignerWithAddress, args?: WriteOptionArgs) {
  const defaults = getOptionDefaults();

  return premiaOption
    .connect(user)
    .writeOption(
      args?.address ?? defaults.address,
      args?.expiration ?? defaults.expiration,
      args?.strikePrice ?? defaults.strikePrice,
      args?.isCall == undefined ? defaults.isCall : args.isCall,
      args?.contractAmount == undefined
        ? defaults.contractAmount
        : args?.contractAmount,
    );
}

async function mintAndWriteOption(
  user: SignerWithAddress,
  contractAmount: number,
  isCall = true,
) {
  if (isCall) {
    await eth.connect(user).mint(utils.parseEther(contractAmount.toString()));
    await eth
      .connect(user)
      .increaseAllowance(
        premiaOption.address,
        utils.parseEther(contractAmount.toString()),
      );
  } else {
    const amount = 10 * contractAmount;
    await dai.connect(user).mint(utils.parseEther(amount.toString()));
    await dai
      .connect(user)
      .increaseAllowance(
        premiaOption.address,
        utils.parseEther(amount.toString()),
      );
  }

  await writeOption(user, { contractAmount, isCall });
}

async function addEthAndWriteOptions(contractAmount: number, isCall = true) {
  await addEth();
  await mintAndWriteOption(writer1, contractAmount, isCall);
}

async function transferOptionToUser1(from: SignerWithAddress, amount?: number) {
  await premiaOption
    .connect(from)
    .safeTransferFrom(from.address, user1.address, 1, amount ?? 1, '0x00');
}

async function exerciseOption(isCall: boolean, amountToExercise: number) {
  if (isCall) {
    await dai
      .connect(user1)
      .mint(utils.parseEther(String(amountToExercise * 10)));
    await dai
      .connect(user1)
      .increaseAllowance(
        premiaOption.address,
        utils.parseEther(String(amountToExercise * 10)),
      );
  } else {
    await eth
      .connect(user1)
      .mint(utils.parseEther(amountToExercise.toString()));
    await eth
      .connect(user1)
      .increaseAllowance(
        premiaOption.address,
        utils.parseEther(amountToExercise.toString()),
      );
  }

  await premiaOption.connect(user1).exerciseOption(1, amountToExercise);
}

async function addEthAndWriteOptionsAndExercise(
  isCall: boolean,
  amountToWrite: number,
  amountToExercise: number,
) {
  await addEthAndWriteOptions(amountToWrite, isCall);
  await transferOptionToUser1(writer1, amountToWrite);
  await exerciseOption(isCall, amountToExercise);
}

describe('PremiaOption', function () {
  beforeEach(async () => {
    [writer1, writer2, user1] = await ethers.getSigners();
    const erc20Factory = new TestErc20Factory(writer1);
    eth = await erc20Factory.deploy();
    dai = await erc20Factory.deploy();

    const premiaOptionFactory = new TestPremiaOptionFactory(writer1);
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
      await expect(writeOption(writer1)).to.be.revertedWith(
        'Token not supported',
      );
    });

    it('should revert if contract amount <= 0', async () => {
      await addEth();
      await expect(
        writeOption(writer1, { contractAmount: 0 }),
      ).to.be.revertedWith('Contract amount must be > 0');
    });

    it('should revert if contract strike price <= 0', async () => {
      await addEth();
      await expect(writeOption(writer1, { strikePrice: 0 })).to.be.revertedWith(
        'Strike price must be > 0',
      );
    });

    it('should revert if strike price increment is wrong', async () => {
      await addEth();
      await expect(
        writeOption(writer1, { strikePrice: utils.parseEther('1') }),
      ).to.be.revertedWith('Wrong strikePrice increment');
    });

    it('should revert if timestamp already passed', async () => {
      await addEth();
      await premiaOption.setTimestamp(700000);
      await expect(writeOption(writer1)).to.be.revertedWith(
        'Expiration already passed',
      );
    });

    it('should revert if timestamp increment is wrong', async () => {
      await addEth();
      await expect(
        writeOption(writer1, { expiration: 200 }),
      ).to.be.revertedWith('Wrong expiration timestamp increment');
    });

    it('should fail if address does not have enough ether for call', async () => {
      await addEth();
      await eth.mint(utils.parseEther('0.99'));
      await eth.increaseAllowance(premiaOption.address, utils.parseEther('1'));
      await expect(writeOption(writer1)).to.be.revertedWith(
        'ERC20: transfer amount exceeds balance',
      );
    });

    it('should fail if address does not have enough dai for put', async () => {
      await addEth();
      await dai.mint(utils.parseEther('9.99'));
      await dai.increaseAllowance(premiaOption.address, utils.parseEther('10'));
      await expect(writeOption(writer1, { isCall: false })).to.be.revertedWith(
        'ERC20: transfer amount exceeds balance',
      );
    });

    it('should successfully mint 2 options', async () => {
      await addEthAndWriteOptions(2);
      const balance = await premiaOption.balanceOf(writer1.address, 1);
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

      let optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      let ethBalance = await eth.balanceOf(writer1.address);

      expect(optionBalance).to.eq(2);
      expect(ethBalance).to.eq(0);

      await premiaOption.cancelOption(1, 1);

      optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      ethBalance = await eth.balanceOf(writer1.address);

      expect(optionBalance).to.eq(1);
      expect(ethBalance.toString()).to.eq(utils.parseEther('1').toString());
    });

    it('should successfully cancel 1 put option', async () => {
      await addEthAndWriteOptions(2, false);

      let optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      let daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance).to.eq(2);
      expect(daiBalance).to.eq(0);

      await premiaOption.cancelOption(1, 1);

      optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance).to.eq(1);
      expect(daiBalance.toString()).to.eq(utils.parseEther('10').toString());
    });

    it('should fail cancelling option if not a writer', async () => {
      await addEthAndWriteOptions(2);
      await transferOptionToUser1(writer1);
      await expect(
        premiaOption.connect(user1).cancelOption(1, 1),
      ).to.revertedWith('Cant cancel more options than written');
    });

    it('should subtract option written after cancelling', async () => {
      await addEthAndWriteOptions(2);
      await premiaOption.cancelOption(1, 1);
      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);
      expect(nbWritten).to.eq(1);
    });
  });

  describe('exerciseOption', () => {
    it('should fail exercising call option if not owned', async () => {
      await addEthAndWriteOptions(2);
      await expect(
        premiaOption.connect(user1).exerciseOption(1, 1),
      ).to.revertedWith('ERC1155: burn amount exceeds balance');
    });

    it('should fail exercising call option if not enough dai', async () => {
      await addEthAndWriteOptions(2);
      await transferOptionToUser1(writer1);
      await expect(
        premiaOption.connect(user1).exerciseOption(1, 1),
      ).to.revertedWith('ERC20: transfer amount exceeds balance');
    });

    it('should successfully exercise 1 call option', async () => {
      await addEthAndWriteOptionsAndExercise(true, 2, 1);

      const nftBalance = await premiaOption.balanceOf(user1.address, 1);
      const daiBalance = await dai.balanceOf(user1.address);
      const ethBalance = await eth.balanceOf(user1.address);

      expect(nftBalance).to.eq(1);
      expect(daiBalance).to.eq(0);
      expect(ethBalance).to.eq(utils.parseEther('1'));
    });

    it('should successfully exercise 1 put option', async () => {
      await addEthAndWriteOptionsAndExercise(false, 2, 1);

      const nftBalance = await premiaOption.balanceOf(user1.address, 1);
      const daiBalance = await dai.balanceOf(user1.address);
      const ethBalance = await eth.balanceOf(user1.address);

      expect(nftBalance).to.eq(1);
      expect(daiBalance).to.eq(utils.parseEther('10'));
      expect(ethBalance).to.eq(0);
    });
  });

  describe('withdraw', () => {
    it('should fail withdrawing if option not expired', async () => {
      await addEthAndWriteOptionsAndExercise(true, 2, 1);
      await expect(premiaOption.withdraw(1)).to.revertedWith(
        'Option not expired',
      );
    });

    it('should fail withdrawing from non-writer if option is expired', async () => {
      await addEthAndWriteOptions(2);
      await transferOptionToUser1(writer1);
      await premiaOption.setTimestamp(1e6);
      await expect(premiaOption.connect(user1).withdraw(1)).to.revertedWith(
        'No option funds to claim for this address',
      );
    });

    it('should successfully allow writer withdrawal of 2 eth if 0/2 call option exercised', async () => {
      await addEthAndWriteOptions(2);
      await transferOptionToUser1(writer1, 2);
      await premiaOption.setTimestamp(1e6);

      let ethBalance = await eth.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(ethBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      ethBalance = await eth.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(ethBalance).to.eq(utils.parseEther('2'));
      expect(daiBalance).to.eq(0);
    });

    it('should successfully allow writer withdrawal of 1 eth and 10 dai if 1/2 call option exercised', async () => {
      await addEthAndWriteOptionsAndExercise(true, 2, 1);
      await premiaOption.setTimestamp(1e6);

      let ethBalance = await eth.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(ethBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      ethBalance = await eth.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(ethBalance).to.eq(utils.parseEther('1'));
      expect(daiBalance).to.eq(utils.parseEther('10'));
    });

    it('should successfully allow writer withdrawal of 20 dai if 2/2 call option exercised', async () => {
      await addEthAndWriteOptionsAndExercise(true, 2, 2);
      await premiaOption.setTimestamp(1e6);

      let ethBalance = await eth.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(ethBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      ethBalance = await eth.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(ethBalance).to.eq(0);
      expect(daiBalance).to.eq(utils.parseEther('20'));
    });

    it('should successfully allow writer withdrawal of 20 dai if 0/2 put option exercised', async () => {
      await addEthAndWriteOptions(2, false);
      await transferOptionToUser1(writer1, 2);
      await premiaOption.setTimestamp(1e6);

      let ethBalance = await eth.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(ethBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      ethBalance = await eth.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(ethBalance).to.eq(0);
      expect(daiBalance).to.eq(utils.parseEther('20'));
    });

    it('should successfully allow writer withdrawal of 1 eth and 10 dai if 1/2 put option exercised', async () => {
      await addEthAndWriteOptionsAndExercise(false, 2, 1);
      await premiaOption.setTimestamp(1e6);

      let ethBalance = await eth.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(ethBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      ethBalance = await eth.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(ethBalance).to.eq(utils.parseEther('1'));
      expect(daiBalance).to.eq(utils.parseEther('10'));
    });

    it('should successfully allow writer withdrawal of 2 eth if 2/2 put option exercised', async () => {
      await addEthAndWriteOptionsAndExercise(false, 2, 2);
      await premiaOption.setTimestamp(1e6);

      let ethBalance = await eth.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(ethBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      ethBalance = await eth.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(ethBalance).to.eq(utils.parseEther('2'));
      expect(daiBalance).to.eq(0);
    });

    it('should withdraw 0.5 eth and 5 dai if 1/2 option exercised and 2 different writers', async () => {
      await addEth();

      await mintAndWriteOption(writer1, 1);
      await mintAndWriteOption(writer2, 1);

      await transferOptionToUser1(writer1);
      await transferOptionToUser1(writer2);

      await exerciseOption(true, 1);
      await premiaOption.setTimestamp(1e6);

      await premiaOption.connect(writer1).withdraw(1);
      await premiaOption.connect(writer2).withdraw(1);

      const writer1Eth = await eth.balanceOf(writer1.address);
      const writer1Dai = await dai.balanceOf(writer1.address);

      const writer2Eth = await eth.balanceOf(writer2.address);
      const writer2Dai = await dai.balanceOf(writer2.address);

      expect(writer1Eth).to.eq(utils.parseEther('0.5'));
      expect(writer1Dai).to.eq(utils.parseEther('5'));

      expect(writer2Eth).to.eq(utils.parseEther('0.5'));
      expect(writer2Dai).to.eq(utils.parseEther('5'));
    });
  });
});
