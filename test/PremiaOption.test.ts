import { ethers } from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  PremiaReferral,
  PremiaReferral__factory,
  TestErc20__factory,
  TestPremiaOption,
  TestPremiaOption__factory,
  TestPremiaStaking,
  TestPremiaStaking__factory,
} from '../contractsTyped';
import { TestErc20 } from '../contractsTyped';
import { PremiaOptionTestUtil } from './utils/PremiaOptionTestUtil';
import { ZERO_ADDRESS } from './utils/constants';

let eth: TestErc20;
let dai: TestErc20;
let premiaOption: TestPremiaOption;
let premiaReferral: PremiaReferral;
let premiaStaking: TestPremiaStaking;
let admin: SignerWithAddress;
let writer1: SignerWithAddress;
let writer2: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
const tax = 0.01;

let optionTestUtil: PremiaOptionTestUtil;

describe('PremiaOption', () => {
  beforeEach(async () => {
    [admin, writer1, writer2, user1, treasury] = await ethers.getSigners();
    const erc20Factory = new TestErc20__factory(admin);
    eth = await erc20Factory.deploy();
    dai = await erc20Factory.deploy();

    const premiaOptionFactory = new TestPremiaOption__factory(admin);
    const premiaReferralFactory = new PremiaReferral__factory(admin);
    const premiaStakingFactory = new TestPremiaStaking__factory(admin);

    premiaOption = await premiaOptionFactory.deploy(
      'dummyURI',
      dai.address,
      eth.address,
      treasury.address,
    );
    premiaReferral = await premiaReferralFactory.deploy();
    premiaStaking = await premiaStakingFactory.deploy();

    await premiaReferral.addWhitelisted([premiaOption.address]);
    await premiaOption.setPremiaReferral(premiaReferral.address);
    await premiaOption.setPremiaStaking(premiaStaking.address);

    optionTestUtil = new PremiaOptionTestUtil({
      eth,
      dai,
      premiaOption,
      admin,
      writer1,
      writer2,
      user1,
      treasury,
      tax,
    });
  });

  it('Should add eth for trading', async () => {
    await optionTestUtil.addEth();
    const settings = await premiaOption.tokenSettings(eth.address);
    expect(settings.contractSize.eq(utils.parseEther('1'))).to.true;
    expect(settings.strikePriceIncrement.eq(utils.parseEther('10'))).to.true;
  });

  it('Should automatically add eth if tokenSettingsCalculator is set, when writing option', async () => {
    await optionTestUtil.addTokenSettingsCalculator();
    let tokenSettings = await premiaOption.tokenSettings(eth.address);

    expect(tokenSettings.strikePriceIncrement).to.eq(0);
    expect(tokenSettings.contractSize).to.eq(0);

    await optionTestUtil.mintAndWriteOption(writer2, 1);
    tokenSettings = await premiaOption.tokenSettings(eth.address);

    expect(tokenSettings.strikePriceIncrement).to.eq(utils.parseEther('10'));
    expect(tokenSettings.contractSize).to.eq(utils.parseEther('1'));
  });

  describe('writeOption', () => {
    it('should fail if token not added', async () => {
      await expect(optionTestUtil.writeOption(writer1)).to.be.revertedWith(
        'Token not supported',
      );
    });

    it('should disable eth for writing', async () => {
      await optionTestUtil.addEth();
      await premiaOption.setTokenDisabled(eth.address, true);
      await expect(optionTestUtil.writeOption(writer1)).to.be.revertedWith(
        'Token is disabled',
      );
    });

    it('should revert if contract amount <= 0', async () => {
      await optionTestUtil.addEth();
      await expect(
        optionTestUtil.writeOption(writer1, { contractAmount: 0 }),
      ).to.be.revertedWith('Contract amount must be > 0');
    });

    it('should revert if contract strike price <= 0', async () => {
      await optionTestUtil.addEth();
      await expect(
        optionTestUtil.writeOption(writer1, { strikePrice: 0 }),
      ).to.be.revertedWith('Strike price must be > 0');
    });

    it('should revert if strike price increment is wrong', async () => {
      await optionTestUtil.addEth();
      await expect(
        optionTestUtil.writeOption(writer1, {
          strikePrice: utils.parseEther('1'),
        }),
      ).to.be.revertedWith('Wrong strikePrice increment');
    });

    it('should revert if timestamp already passed', async () => {
      await optionTestUtil.addEth();
      await premiaOption.setTimestamp(1e6);
      await expect(optionTestUtil.writeOption(writer1)).to.be.revertedWith(
        'Expiration already passed',
      );
    });

    it('should revert if timestamp increment is wrong', async () => {
      await optionTestUtil.addEth();
      await expect(
        optionTestUtil.writeOption(writer1, { expiration: 200 }),
      ).to.be.revertedWith('Wrong expiration timestamp increment');
    });

    it('should revert if timestamp is beyond max expiration', async () => {
      await optionTestUtil.addEth();
      await expect(
        optionTestUtil.writeOption(writer1, { expiration: 3600 * 24 * 400 }),
      ).to.be.revertedWith('Expiration must be <= 1 year');
    });

    it('should fail if address does not have enough ether for call', async () => {
      await optionTestUtil.addEth();
      await eth.mint(utils.parseEther('0.99'));
      await eth.increaseAllowance(premiaOption.address, utils.parseEther('1'));
      await expect(optionTestUtil.writeOption(writer1)).to.be.revertedWith(
        'ERC20: transfer amount exceeds balance',
      );
    });

    it('should fail if address does not have enough dai for put', async () => {
      await optionTestUtil.addEth();
      await dai.mint(utils.parseEther('9.99'));
      await dai.increaseAllowance(premiaOption.address, utils.parseEther('10'));
      await expect(
        optionTestUtil.writeOption(writer1, { isCall: false }),
      ).to.be.revertedWith('ERC20: transfer amount exceeds balance');
    });

    it('should successfully mint 2 options', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      const balance = await premiaOption.balanceOf(writer1.address, 1);
      expect(balance).to.eq(2);
    });

    it('should be optionId 1', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      const defaults = optionTestUtil.getOptionDefaults();
      const optionId = await premiaOption.getOptionId(
        eth.address,
        defaults.expiration,
        defaults.strikePrice,
        defaults.isCall,
      );
      expect(optionId).to.eq(1);
    });

    it('should successfully batchWriteOption', async () => {
      await optionTestUtil.addEth();

      const defaultOption = optionTestUtil.getOptionDefaults();

      const contractAmount1 = 2;
      const contractAmount2 = 3;

      let amount = utils
        .parseEther(contractAmount1.toString())
        .mul(1e5 + tax * 1e5)
        .div(1e5);
      await eth.connect(writer1).mint(amount.toString());
      await eth
        .connect(writer1)
        .increaseAllowance(
          premiaOption.address,
          utils.parseEther(amount.toString()),
        );

      amount = utils
        .parseEther(contractAmount2.toString())
        .mul(10)
        .mul(3)
        .mul(1e5 + tax * 1e5)
        .div(1e5);
      await dai.connect(writer1).mint(utils.parseEther(amount.toString()));
      await dai
        .connect(writer1)
        .increaseAllowance(
          premiaOption.address,
          utils.parseEther(amount.toString()),
        );

      await premiaOption.connect(writer1).batchWriteOption(
        [
          {
            ...defaultOption,
            token: eth.address,
            isCall: true,
            contractAmount: contractAmount1,
          },
          {
            ...defaultOption,
            token: eth.address,
            isCall: false,
            contractAmount: contractAmount2,
          },
        ],
        ZERO_ADDRESS,
      );

      const balance1 = await premiaOption.balanceOf(writer1.address, 1);
      const balance2 = await premiaOption.balanceOf(writer1.address, 2);
      expect(balance1).to.eq(contractAmount1);
      expect(balance2).to.eq(contractAmount2);
    });
  });

  describe('cancelOption', () => {
    it('should successfully cancel 1 call option', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);

      let optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      let ethBalance = await eth.balanceOf(writer1.address);

      expect(optionBalance).to.eq(2);
      expect(ethBalance).to.eq(0);

      await premiaOption.connect(writer1).cancelOption(1, 1);

      optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      ethBalance = await eth.balanceOf(writer1.address);

      expect(optionBalance).to.eq(1);
      expect(ethBalance.toString()).to.eq(utils.parseEther('1').toString());
    });

    it('should successfully cancel 1 put option', async () => {
      await optionTestUtil.addEthAndWriteOptions(2, false);

      let optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      let daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance).to.eq(2);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).cancelOption(1, 1);

      optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance).to.eq(1);
      expect(daiBalance.toString()).to.eq(utils.parseEther('10').toString());
    });

    it('should fail cancelling option if not a writer', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await optionTestUtil.transferOptionToUser1(writer1);
      await expect(
        premiaOption.connect(user1).cancelOption(1, 1),
      ).to.revertedWith('Cant cancel more options than written');
    });

    it('should subtract option written after cancelling', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await premiaOption.connect(writer1).cancelOption(1, 1);
      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);
      expect(nbWritten).to.eq(1);
    });

    it('should successfully batchCancelOption', async () => {
      await optionTestUtil.addEthAndWriteOptions(3);
      await optionTestUtil.addEthAndWriteOptions(3, false);

      let optionBalance1 = await premiaOption.balanceOf(writer1.address, 1);
      let optionBalance2 = await premiaOption.balanceOf(writer1.address, 2);
      let ethBalance = await eth.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance1).to.eq(3);
      expect(ethBalance).to.eq(0);
      expect(optionBalance2).to.eq(3);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).batchCancelOption([1, 2], [2, 1]);

      optionBalance1 = await premiaOption.balanceOf(writer1.address, 1);
      optionBalance2 = await premiaOption.balanceOf(writer1.address, 2);

      ethBalance = await eth.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance1).to.eq(1);
      expect(optionBalance2).to.eq(2);
      expect(ethBalance.toString()).to.eq(utils.parseEther('2').toString());
      expect(daiBalance.toString()).to.eq(utils.parseEther('10').toString());
    });
  });

  describe('exerciseOption', () => {
    it('should fail exercising call option if not owned', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await expect(
        premiaOption.connect(user1).exerciseOption(1, 1, ZERO_ADDRESS),
      ).to.revertedWith('ERC1155: burn amount exceeds balance');
    });

    it('should fail exercising call option if not enough dai', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await optionTestUtil.transferOptionToUser1(writer1);
      await expect(
        premiaOption.connect(user1).exerciseOption(1, 1, ZERO_ADDRESS),
      ).to.revertedWith('ERC20: transfer amount exceeds balance');
    });

    it('should successfully exercise 1 call option', async () => {
      await optionTestUtil.addEthAndWriteOptionsAndExercise(true, 2, 1);

      const nftBalance = await premiaOption.balanceOf(user1.address, 1);
      const daiBalance = await dai.balanceOf(user1.address);
      const ethBalance = await eth.balanceOf(user1.address);

      expect(nftBalance).to.eq(1);
      expect(daiBalance).to.eq(0);
      expect(ethBalance).to.eq(utils.parseEther('1'));
    });

    it('should successfully exercise 1 put option', async () => {
      await optionTestUtil.addEthAndWriteOptionsAndExercise(false, 2, 1);

      const nftBalance = await premiaOption.balanceOf(user1.address, 1);
      const daiBalance = await dai.balanceOf(user1.address);
      const ethBalance = await eth.balanceOf(user1.address);

      expect(nftBalance).to.eq(1);
      expect(daiBalance).to.eq(utils.parseEther('10'));
      expect(ethBalance).to.eq(0);
    });

    it('should have 0.01 eth and 0.1 dai in treasury after 1 option exercised', async () => {
      await optionTestUtil.addEthAndWriteOptionsAndExercise(true, 1, 1);

      const daiBalance = await dai.balanceOf(treasury.address);
      const ethBalance = await eth.balanceOf(treasury.address);

      expect(daiBalance).to.eq(utils.parseEther('0.1'));
      expect(ethBalance).to.eq(utils.parseEther('0.01'));
    });

    it('should successfully batchExerciseOption', async () => {
      await optionTestUtil.addEthAndWriteOptions(2, true);
      await optionTestUtil.addEthAndWriteOptions(3, false);

      await optionTestUtil.transferOptionToUser1(writer1, 2, 1);
      await optionTestUtil.transferOptionToUser1(writer1, 3, 2);

      let amount = 1 * 10 * (1 + tax);
      await dai.connect(user1).mint(utils.parseEther(amount.toString()));
      await dai
        .connect(user1)
        .increaseAllowance(
          premiaOption.address,
          utils.parseEther(amount.toString()),
        );

      amount = 2 * (1 + tax);

      await eth.connect(user1).mint(utils.parseEther(amount.toString()));
      await eth
        .connect(user1)
        .increaseAllowance(
          premiaOption.address,
          utils.parseEther(amount.toString()),
        );

      await premiaOption
        .connect(user1)
        .batchExerciseOption([1, 2], [1, 2], ZERO_ADDRESS);

      const nftBalance1 = await premiaOption.balanceOf(user1.address, 1);
      const nftBalance2 = await premiaOption.balanceOf(user1.address, 2);
      const daiBalance = await dai.balanceOf(user1.address);
      const ethBalance = await eth.balanceOf(user1.address);

      expect(nftBalance1).to.eq(1);
      expect(nftBalance2).to.eq(1);
      expect(daiBalance).to.eq(utils.parseEther('20'));
      expect(ethBalance).to.eq(utils.parseEther('1'));
    });
  });

  describe('withdraw', () => {
    it('should fail withdrawing if option not expired', async () => {
      await optionTestUtil.addEthAndWriteOptionsAndExercise(true, 2, 1);
      await expect(premiaOption.withdraw(1)).to.revertedWith(
        'Option not expired',
      );
    });

    it('should fail withdrawing from non-writer if option is expired', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await optionTestUtil.transferOptionToUser1(writer1);
      await premiaOption.setTimestamp(1e6);
      await expect(premiaOption.connect(user1).withdraw(1)).to.revertedWith(
        'No option funds to claim for this address',
      );
    });

    it('should successfully allow writer withdrawal of 2 eth if 0/2 call option exercised', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await optionTestUtil.transferOptionToUser1(writer1, 2);
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
      await optionTestUtil.addEthAndWriteOptionsAndExercise(true, 2, 1);
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
      await optionTestUtil.addEthAndWriteOptionsAndExercise(true, 2, 2);
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
      await optionTestUtil.addEthAndWriteOptions(2, false);
      await optionTestUtil.transferOptionToUser1(writer1, 2);
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
      await optionTestUtil.addEthAndWriteOptionsAndExercise(false, 2, 1);
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
      await optionTestUtil.addEthAndWriteOptionsAndExercise(false, 2, 2);
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
      await optionTestUtil.addEth();

      await optionTestUtil.mintAndWriteOption(writer1, 1);
      await optionTestUtil.mintAndWriteOption(writer2, 1);

      await optionTestUtil.transferOptionToUser1(writer1);
      await optionTestUtil.transferOptionToUser1(writer2);

      await optionTestUtil.exerciseOption(true, 1);
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

    it('should withdraw 1 eth, if 1/2 call exercised and 1 withdrawPreExpiration', async () => {
      await optionTestUtil.addEth();
      await optionTestUtil.mintAndWriteOption(writer1, 1);
      await optionTestUtil.mintAndWriteOption(writer2, 1);
      await optionTestUtil.transferOptionToUser1(writer1, 1);
      await optionTestUtil.transferOptionToUser1(writer2, 1);
      await optionTestUtil.exerciseOption(true, 1);

      await premiaOption.connect(writer2).withdrawPreExpiration(1, 1);

      await premiaOption.setTimestamp(1e6);

      await premiaOption.connect(writer1).withdraw(1);

      const daiBalance = await dai.balanceOf(writer1.address);
      const ethBalance = await eth.balanceOf(writer1.address);

      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);

      expect(daiBalance).to.eq(0);
      expect(ethBalance).to.eq(utils.parseEther('1'));
      expect(nbWritten).to.eq(0);
    });

    it('should withdraw 10 dai, if 1/2 put exercised and 1 withdrawPreExpiration', async () => {
      await optionTestUtil.addEth();
      await optionTestUtil.mintAndWriteOption(writer1, 1, false);
      await optionTestUtil.mintAndWriteOption(writer2, 1, false);
      await optionTestUtil.transferOptionToUser1(writer1, 1);
      await optionTestUtil.transferOptionToUser1(writer2, 1);
      await optionTestUtil.exerciseOption(false, 1);

      await premiaOption.connect(writer2).withdrawPreExpiration(1, 1);

      await premiaOption.setTimestamp(1e6);

      await premiaOption.connect(writer1).withdraw(1);

      const daiBalance = await dai.balanceOf(writer1.address);
      const ethBalance = await eth.balanceOf(writer1.address);

      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);

      expect(daiBalance).to.eq(utils.parseEther('10'));
      expect(ethBalance).to.eq(0);
      expect(nbWritten).to.eq(0);
    });

    it('should successfully batchWithdraw', async () => {
      await optionTestUtil.addEth();
      await optionTestUtil.mintAndWriteOption(writer1, 1);
      await optionTestUtil.mintAndWriteOption(writer2, 1);
      await optionTestUtil.transferOptionToUser1(writer1, 1);
      await optionTestUtil.transferOptionToUser1(writer2, 1);
      await optionTestUtil.exerciseOption(true, 1);

      await premiaOption.connect(writer2).withdrawPreExpiration(1, 1);

      await optionTestUtil.mintAndWriteOption(writer1, 1, false);
      await optionTestUtil.mintAndWriteOption(writer2, 1, false);
      await optionTestUtil.transferOptionToUser1(writer1, 1, 2);
      await optionTestUtil.transferOptionToUser1(writer2, 1, 2);
      await optionTestUtil.exerciseOption(false, 1, undefined, 2);

      await premiaOption.connect(writer2).withdrawPreExpiration(2, 1);

      await premiaOption.setTimestamp(1e6);

      await premiaOption.connect(writer1).batchWithdraw([1, 2]);

      const daiBalance = await dai.balanceOf(writer1.address);
      const ethBalance = await eth.balanceOf(writer1.address);
      const nbWritten1 = await premiaOption.nbWritten(writer1.address, 1);
      const nbWritten2 = await premiaOption.nbWritten(writer1.address, 2);

      expect(daiBalance).to.eq(utils.parseEther('10'));
      expect(ethBalance).to.eq(utils.parseEther('1'));
      expect(nbWritten1).to.eq(0);
      expect(nbWritten2).to.eq(0);
    });
  });

  describe('withdrawPreExpiration', () => {
    it('should fail withdrawing if option is expired', async () => {
      await optionTestUtil.addEthAndWriteOptionsAndExercise(true, 2, 1);
      await premiaOption.setTimestamp(1e6);
      await expect(premiaOption.withdrawPreExpiration(1, 1)).to.revertedWith(
        'Option expired',
      );
    });

    it('should fail withdrawing from non-writer if option is not expired', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await optionTestUtil.transferOptionToUser1(writer1);
      await expect(
        premiaOption.connect(user1).withdrawPreExpiration(1, 1),
      ).to.revertedWith('Address does not have enough claims left');
    });

    it('should fail withdrawing if no unclaimed exercised options', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await optionTestUtil.transferOptionToUser1(writer1, 2);

      await expect(
        premiaOption.connect(writer1).withdrawPreExpiration(1, 2),
      ).to.revertedWith('No option to claim funds from');
    });

    it('should fail withdrawing if not enough unclaimed exercised options', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await optionTestUtil.transferOptionToUser1(writer1, 2);
      await optionTestUtil.exerciseOption(true, 1);

      await expect(
        premiaOption.connect(writer1).withdrawPreExpiration(1, 2),
      ).to.revertedWith('Not enough options claimable');
    });

    it('should successfully withdraw 10 dai for withdrawPreExpiration of call option exercised', async () => {
      await optionTestUtil.addEthAndWriteOptions(2);
      await optionTestUtil.transferOptionToUser1(writer1, 2);
      await optionTestUtil.exerciseOption(true, 1);

      await premiaOption.connect(writer1).withdrawPreExpiration(1, 1);

      const daiBalance = await dai.balanceOf(writer1.address);
      const ethBalance = await eth.balanceOf(writer1.address);

      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);

      expect(daiBalance).to.eq(utils.parseEther('10'));
      expect(ethBalance).to.eq(0);
      expect(nbWritten).to.eq(1);
    });

    it('should successfully withdraw 1 eth for withdrawPreExpiration of put option exercised', async () => {
      await optionTestUtil.addEthAndWriteOptions(2, false);
      await optionTestUtil.transferOptionToUser1(writer1, 2);
      await optionTestUtil.exerciseOption(false, 1);

      await premiaOption.connect(writer1).withdrawPreExpiration(1, 1);

      const daiBalance = await dai.balanceOf(writer1.address);
      const ethBalance = await eth.balanceOf(writer1.address);

      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);

      expect(daiBalance).to.eq(0);
      expect(ethBalance).to.eq(utils.parseEther('1'));
      expect(nbWritten).to.eq(1);
    });

    it('should successfully batchWithdrawPreExpiration', async () => {
      await optionTestUtil.addEth();
      await optionTestUtil.mintAndWriteOption(writer1, 3, true);
      await optionTestUtil.mintAndWriteOption(writer1, 3, false);

      await optionTestUtil.transferOptionToUser1(writer1, 3);
      await optionTestUtil.transferOptionToUser1(writer1, 3, 2);
      await optionTestUtil.exerciseOption(true, 2);
      await optionTestUtil.exerciseOption(false, 1, undefined, 2);

      await premiaOption
        .connect(writer1)
        .batchWithdrawPreExpiration([1, 2], [2, 1]);

      const daiBalance = await dai.balanceOf(writer1.address);
      const ethBalance = await eth.balanceOf(writer1.address);

      const nbWritten1 = await premiaOption.nbWritten(writer1.address, 1);
      const nbWritten2 = await premiaOption.nbWritten(writer1.address, 2);

      expect(daiBalance).to.eq(utils.parseEther('20'));
      expect(ethBalance).to.eq(utils.parseEther('1'));
      expect(nbWritten1).to.eq(1);
      expect(nbWritten2).to.eq(2);
    });
  });

  describe('referral', () => {
    it('should register user1 as referrer', async () => {
      await optionTestUtil.addEthAndWriteOptions(2, true, user1.address);
      const referrer = await premiaReferral.referrals(writer1.address);
      expect(referrer).to.eq(user1.address);
    });

    it('should keep user1 as referrer, if try to set another referrer', async () => {
      await optionTestUtil.addEthAndWriteOptions(2, true, user1.address);
      await optionTestUtil.addEthAndWriteOptions(2, true, writer2.address);
      const referrer = await premiaReferral.referrals(writer1.address);
      expect(referrer).to.eq(user1.address);
    });

    it('should give user with referrer, 10% discount on write fee + give referrer 10% of fee', async () => {
      await optionTestUtil.addEthAndWriteOptions(2, true, user1.address);

      const writer1Options = await premiaOption.balanceOf(writer1.address, 1);
      const writer1Eth = await eth.balanceOf(writer1.address);
      const referrerEth = await eth.balanceOf(user1.address);

      expect(writer1Options).to.eq(2);
      expect(writer1Eth).to.eq(
        ethers.utils.parseEther('0.02').div(10), // Expect 10% of tax of 2 options writing
      );
      expect(referrerEth).to.eq(
        ethers.utils.parseEther('0.02').mul(9).div(10).div(10), // Expect 10% of 90% of tax for 2 options
      );
    });

    it('should give user with referrer, 10% discount on exercise fee + give referrer 10% of fee', async () => {
      await optionTestUtil.addEthAndWriteOptionsAndExercise(
        true,
        2,
        2,
        writer2.address,
      );

      const user1Options = await premiaOption.balanceOf(writer1.address, 1);
      const user1Dai = await dai.balanceOf(user1.address);
      const referrerDai = await dai.balanceOf(writer2.address);

      expect(user1Options).to.eq(0);
      expect(user1Dai).to.eq(
        BigNumber.from(ethers.utils.parseEther('0.2')).div(10), // Expect 10% of the 1% tax of 2 options exercised at strike price of 10 DAI
      );
      expect(referrerDai).to.eq(
        ethers.utils.parseEther('0.2').mul(9).div(10).div(10), // Expect 10% of 90% of tax
      );
    });
  });

  describe('fees', () => {
    it('should calculate total fee correctly without discount', async () => {
      const fee = await premiaOption.getTotalFee(
        writer1.address,
        utils.parseEther('2'),
        false,
        true,
      );

      expect(fee).to.eq(utils.parseEther('0.02'));
    });

    it('should calculate total fee correctly with a referral', async () => {
      await optionTestUtil.addEthAndWriteOptions(2, true, user1.address);
      const fee = await premiaOption.getTotalFee(
        writer1.address,
        utils.parseEther('2'),
        false,
        true,
      );

      expect(fee).to.eq(utils.parseEther('0.018'));
    });

    it('should correctly calculate total fee with a referral + staking discount', async () => {
      await premiaOption.setPre;
      await premiaStaking.setDiscount(2e4);
      const fee = await premiaOption.getTotalFee(
        writer1.address,
        utils.parseEther('2'),
        true,
        true,
      );

      expect(fee).to.eq(utils.parseEther('0.0144'));
    });
  });
});
