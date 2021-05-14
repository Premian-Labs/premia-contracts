import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  PremiaOption,
  PremiaOption__factory,
  TestErc20,
  TestErc20__factory,
  TestFlashLoan__factory,
  TestPremiaFeeDiscount,
  TestPremiaFeeDiscount__factory,
  WETH9,
  WETH9__factory,
} from '../contractsTyped';
import { PremiaOptionTestUtil } from './utils/PremiaOptionTestUtil';
import {
  ONE_WEEK,
  TEST_TOKEN_DECIMALS,
  TEST_USE_WETH,
} from './utils/constants';
import { resetHardhat, setTimestampPostExpiration } from './utils/evm';
import { deployContracts, IPremiaContracts } from '../scripts/deployContracts';
import { parseEther } from 'ethers/lib/utils';
import { createUniswap, IUniswap } from './utils/uniswap';
import {
  getAmountExceedsBalanceRevertMsg,
  getToken,
  mintTestToken,
  parseTestToken,
} from './utils/token';

let p: IPremiaContracts;
let uniswap: IUniswap;
let weth: WETH9;
let wbtc: TestErc20;
let dai: TestErc20;
let premiaOption: PremiaOption;
let premiaFeeDiscount: TestPremiaFeeDiscount;
let admin: SignerWithAddress;
let writer1: SignerWithAddress;
let writer2: SignerWithAddress;
let user1: SignerWithAddress;
let feeRecipient: SignerWithAddress;
let testToken: WETH9 | TestErc20;
const tax = 100;

let optionTestUtil: PremiaOptionTestUtil;

describe('PremiaOption', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, writer1, writer2, user1, feeRecipient] = await ethers.getSigners();
    weth = await new WETH9__factory(admin).deploy();
    dai = await new TestErc20__factory(admin).deploy(18);
    wbtc = await new TestErc20__factory(admin).deploy(TEST_TOKEN_DECIMALS);

    testToken = getToken(weth, wbtc);

    p = await deployContracts(admin, feeRecipient.address, true);

    const premiaOptionFactory = new PremiaOption__factory(admin);

    premiaOption = await premiaOptionFactory.deploy(
      'dummyURI',
      dai.address,
      p.feeCalculator.address,
      feeRecipient.address,
    );

    premiaFeeDiscount = await new TestPremiaFeeDiscount__factory(
      admin,
    ).deploy();
    await p.feeCalculator.setPremiaFeeDiscount(premiaFeeDiscount.address);

    optionTestUtil = new PremiaOptionTestUtil({
      testToken,
      dai,
      premiaOption,
      admin,
      writer1,
      writer2,
      user1,
      feeRecipient,
      tax,
    });
  });

  it('should add testToken for trading', async () => {
    await optionTestUtil.addTestToken();
    const strikePriceIncrement = await premiaOption.tokenStrikeIncrement(
      testToken.address,
    );
    expect(strikePriceIncrement.eq(parseEther('10'))).to.true;
  });

  it('should create a new optionId', async () => {
    await optionTestUtil.addTestToken();
    const defaultOption = optionTestUtil.getOptionDefaults();
    await premiaOption.getOptionIdOrCreate(
      testToken.address,
      defaultOption.expiration,
      defaultOption.strikePrice,
      true,
    );

    const option = await premiaOption.optionData(1);
    expect(option.token).to.eq(testToken.address);
    expect(option.expiration).to.eq(defaultOption.expiration);
    expect(option.strikePrice).to.eq(defaultOption.strikePrice);
    expect(option.isCall).to.be.true;
  });

  describe('writeOption', () => {
    it('should fail if token not added', async () => {
      await expect(optionTestUtil.writeOption(writer1)).to.be.revertedWith(
        'Token not supported',
      );
    });

    it('should disable testToken for writing', async () => {
      await optionTestUtil.addTestToken();
      await premiaOption.setTokens([testToken.address], [0]);
      await expect(optionTestUtil.writeOption(writer1)).to.be.revertedWith(
        'Token not supported',
      );
    });

    it('should revert if contract amount <= 0', async () => {
      await optionTestUtil.addTestToken();
      await expect(
        optionTestUtil.writeOption(writer1, { amount: BigNumber.from(0) }),
      ).to.be.revertedWith('Amount <= 0');
    });

    it('should revert if contract strike price <= 0', async () => {
      await optionTestUtil.addTestToken();
      await expect(
        optionTestUtil.writeOption(writer1, { strikePrice: 0 }),
      ).to.be.revertedWith('Strike <= 0');
    });

    it('should revert if strike price increment is wrong', async () => {
      await optionTestUtil.addTestToken();
      await expect(
        optionTestUtil.writeOption(writer1, {
          strikePrice: parseEther('1'),
        }),
      ).to.be.revertedWith('Wrong strike incr');
    });

    it('should revert if timestamp already passed', async () => {
      await optionTestUtil.addTestToken();
      await setTimestampPostExpiration();
      await expect(optionTestUtil.writeOption(writer1)).to.be.revertedWith(
        'Exp passed',
      );
    });

    it('should revert if timestamp increment is wrong', async () => {
      await optionTestUtil.addTestToken();
      await expect(
        optionTestUtil.writeOption(writer1, {
          expiration: optionTestUtil.getNextExpiration() + 200,
        }),
      ).to.be.revertedWith('Wrong exp incr');
    });

    it('should revert if timestamp is beyond max expiration', async () => {
      await optionTestUtil.addTestToken();
      await expect(
        optionTestUtil.writeOption(writer1, {
          expiration: Math.floor(new Date().getTime() / 1000 + 60 * ONE_WEEK),
        }),
      ).to.be.revertedWith('Exp > 1 yr');
    });

    it('should fail if address does not have enough testToken for call', async () => {
      await optionTestUtil.addTestToken();
      await mintTestToken(writer1, testToken, parseTestToken('0.99'));
      await testToken
        .connect(writer1)
        .approve(premiaOption.address, parseTestToken('1'));
      await expect(optionTestUtil.writeOption(writer1)).to.be.revertedWith(
        getAmountExceedsBalanceRevertMsg(),
      );
    });

    it('should fail if address does not have enough dai for put', async () => {
      await optionTestUtil.addTestToken();
      await dai.mint(writer1.address, parseEther('9.99'));
      await dai
        .connect(writer1)
        .increaseAllowance(premiaOption.address, parseEther('10'));
      await expect(
        optionTestUtil.writeOption(writer1, { isCall: false }),
      ).to.be.revertedWith('ERC20: transfer amount exceeds balance');
    });

    it('should successfully mint options for 2 testToken', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      const balance = await premiaOption.balanceOf(writer1.address, 1);
      expect(balance).to.eq(parseTestToken('2'));
    });

    it('should be optionId 1', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      const defaults = optionTestUtil.getOptionDefaults();
      const optionId = await premiaOption.getOptionId(
        testToken.address,
        defaults.expiration,
        defaults.strikePrice,
        defaults.isCall,
      );
      expect(optionId).to.eq(1);
    });

    it('should successfully batchWriteOption', async () => {
      await optionTestUtil.addTestToken();

      const defaultOption = optionTestUtil.getOptionDefaults();

      const contractAmount1 = parseTestToken('2');
      const contractAmount2 = parseTestToken('3');

      let amount = contractAmount1.add(contractAmount1.mul(tax).div(1e4));
      await mintTestToken(writer1, testToken, amount);
      await testToken
        .connect(writer1)
        .approve(premiaOption.address, parseTestToken(amount.toString()));

      const baseAmount = contractAmount2.mul(10).mul(3);
      amount = baseAmount.add(baseAmount.mul(tax).div(1e4));
      await dai.mint(writer1.address, parseEther(amount.toString()));
      await dai
        .connect(writer1)
        .increaseAllowance(premiaOption.address, parseEther(amount.toString()));

      await premiaOption
        .connect(writer1)
        .setApprovalForAll(p.premiaOptionBatch.address, true);
      await p.premiaOptionBatch.connect(writer1).batchWriteOption(
        premiaOption.address,
        [
          {
            ...defaultOption,
            token: testToken.address,
            isCall: true,
            amount: contractAmount1,
          },
          {
            ...defaultOption,
            token: testToken.address,
            isCall: false,
            amount: contractAmount2,
          },
        ],
      );

      const balance1 = await premiaOption.balanceOf(writer1.address, 1);
      const balance2 = await premiaOption.balanceOf(writer1.address, 2);
      expect(balance1).to.eq(contractAmount1);
      expect(balance2).to.eq(contractAmount2);
    });

    it('should fail writeOptionFrom if not approved', async () => {
      await optionTestUtil.addTestToken();
      const amount = parseTestToken('2');
      const amountWithFee = amount.add(amount.mul(tax).div(1e4));
      await mintTestToken(writer1, testToken, amountWithFee);
      await testToken
        .connect(writer1)
        .approve(premiaOption.address, amountWithFee);

      await expect(
        premiaOption
          .connect(writer2)
          .writeOptionFrom(
            writer1.address,
            { ...optionTestUtil.getOptionDefaults(), amount },
          ),
      ).to.be.revertedWith('Not approved');
    });

    it('should successfully writeOptionFrom', async () => {
      await optionTestUtil.addTestToken();
      const amount = parseTestToken('2');
      const amountWithFee = amount.add(amount.mul(tax).div(1e4));
      await mintTestToken(writer1, testToken, amountWithFee);
      await testToken
        .connect(writer1)
        .approve(premiaOption.address, amountWithFee);

      await premiaOption
        .connect(writer1)
        .setApprovalForAll(writer2.address, true);
      await premiaOption
        .connect(writer2)
        .writeOptionFrom(
          writer1.address,
          { ...optionTestUtil.getOptionDefaults(), amount },
        );

      expect(await premiaOption.balanceOf(writer1.address, 1)).to.eq(amount);
      expect(await premiaOption.nbWritten(writer1.address, 1)).to.eq(amount);
    });
  });

  describe('cancelOption', () => {
    it('should successfully cancel 1 call option', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));

      let optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      let testTokenBalance = await testToken.balanceOf(writer1.address);

      expect(optionBalance).to.eq(parseTestToken('2'));
      expect(testTokenBalance).to.eq(0);

      await premiaOption.connect(writer1).cancelOption(1, parseTestToken('1'));

      optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      testTokenBalance = await testToken.balanceOf(writer1.address);

      expect(optionBalance).to.eq(parseTestToken('1'));
      expect(testTokenBalance.toString()).to.eq(parseTestToken('1'));
    });

    it('should successfully cancel 1 put option', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        false,
      );

      let optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      let daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance).to.eq(parseTestToken('2'));
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).cancelOption(1, parseTestToken('1'));

      optionBalance = await premiaOption.balanceOf(writer1.address, 1);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance).to.eq(parseTestToken('1'));
      expect(daiBalance.toString()).to.eq(parseEther('10'));
    });

    it('should fail cancelling option if not a writer', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1);
      await expect(
        premiaOption.connect(user1).cancelOption(1, parseTestToken('1')),
      ).to.revertedWith('Not enough written');
    });

    it('should subtract option written after cancelling', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await premiaOption.connect(writer1).cancelOption(1, parseTestToken('1'));
      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);
      expect(nbWritten).to.eq(parseTestToken('1'));
    });

    it('should successfully batchCancelOption', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('3'));
      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('3'),
        false,
      );

      let optionBalance1 = await premiaOption.balanceOf(writer1.address, 1);
      let optionBalance2 = await premiaOption.balanceOf(writer1.address, 2);
      let testTokenBalance = await testToken.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance1).to.eq(parseTestToken('3'));
      expect(testTokenBalance).to.eq(0);
      expect(optionBalance2).to.eq(parseTestToken('3'));
      expect(daiBalance).to.eq(0);

      await premiaOption
        .connect(writer1)
        .setApprovalForAll(p.premiaOptionBatch.address, true);
      await p.premiaOptionBatch
        .connect(writer1)
        .batchCancelOption(
          premiaOption.address,
          [1, 2],
          [parseTestToken('2'), parseTestToken('1')],
        );

      optionBalance1 = await premiaOption.balanceOf(writer1.address, 1);
      optionBalance2 = await premiaOption.balanceOf(writer1.address, 2);

      testTokenBalance = await testToken.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(optionBalance1).to.eq(parseTestToken('1'));
      expect(optionBalance2).to.eq(parseTestToken('2'));
      expect(testTokenBalance.toString()).to.eq(parseTestToken('2'));
      expect(daiBalance.toString()).to.eq(parseEther('10'));
    });

    it('should fail cancelOptionFrom if not approved', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        false,
      );

      await expect(
        premiaOption
          .connect(writer2)
          .cancelOptionFrom(writer1.address, 1, parseTestToken('2')),
      ).to.be.revertedWith('Not approved');
    });

    it('should successfully cancelOptionFrom', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        false,
      );

      await premiaOption
        .connect(writer1)
        .setApprovalForAll(writer2.address, true);
      await premiaOption
        .connect(writer2)
        .cancelOptionFrom(writer1.address, 1, parseTestToken('2'));

      expect(await premiaOption.balanceOf(writer1.address, 1)).to.eq(0);
    });
  });

  describe('exerciseOption', () => {
    it('should fail exercising call option if not owned', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await expect(
        premiaOption
          .connect(user1)
          .exerciseOption(1, parseTestToken('1')),
      ).to.revertedWith('ERC1155: burn amount exceeds balance');
    });

    it('should fail exercising call option if not enough dai', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1);
      await expect(
        premiaOption
          .connect(user1)
          .exerciseOption(1, parseTestToken('1')),
      ).to.revertedWith('ERC20: transfer amount exceeds balance');
    });

    it('should successfully exercise 1 call option', async () => {
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('2'),
        parseTestToken('1'),
      );

      const optionBalance = await premiaOption.balanceOf(user1.address, 1);
      const daiBalance = await dai.balanceOf(user1.address);
      const testTokenBalance = await testToken.balanceOf(user1.address);

      expect(optionBalance).to.eq(parseTestToken('1'));
      expect(daiBalance).to.eq(0);
      expect(testTokenBalance).to.eq(parseTestToken('1'));
    });

    it('should successfully exercise 1 put option', async () => {
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        false,
        parseTestToken('2'),
        parseTestToken('1'),
      );

      const optionBalance = await premiaOption.balanceOf(user1.address, 1);
      const daiBalance = await dai.balanceOf(user1.address);
      const testTokenBalance = await testToken.balanceOf(user1.address);

      expect(optionBalance).to.eq(parseTestToken('1'));
      expect(daiBalance).to.eq(parseEther('10'));
      expect(testTokenBalance).to.eq(0);
    });

    it('should have 0.01 testToken and 0.1 dai in feeRecipient after 1 option exercised', async () => {
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('1'),
        parseTestToken('1'),
      );

      const daiBalance = await dai.balanceOf(feeRecipient.address);
      const testTokenBalance = await testToken.balanceOf(feeRecipient.address);

      expect(daiBalance).to.eq(parseEther('0.1'));
      expect(testTokenBalance).to.eq(parseTestToken('0.01'));
    });

    it('should have 0 testToken and 0.1 dai in feeRecipient after 1 option exercised if writer is whitelisted', async () => {
      await p.feeCalculator.addWhitelisted([writer1.address]);
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('1'),
        parseTestToken('1'),
      );

      const daiBalance = await dai.balanceOf(feeRecipient.address);
      const testTokenBalance = await testToken.balanceOf(feeRecipient.address);

      expect(daiBalance).to.eq(parseEther('0.1'));
      expect(testTokenBalance).to.eq(parseTestToken('0'));
    });

    it('should have 0.1 testToken and 0 dai in feeRecipient after 1 option exercised if exerciser is whitelisted', async () => {
      await p.feeCalculator.addWhitelisted([user1.address]);
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('1'),
        parseTestToken('1'),
      );

      const daiBalance = await dai.balanceOf(feeRecipient.address);
      const testTokenBalance = await testToken.balanceOf(feeRecipient.address);

      expect(daiBalance).to.eq(parseEther('0'));
      expect(testTokenBalance).to.eq(parseTestToken('0.01'));
    });

    it('should successfully batchExerciseOption', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        true,
      );
      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('3'),
        false,
      );

      await optionTestUtil.transferOptionToUser1(
        writer1,
        parseTestToken('2'),
        1,
      );
      await optionTestUtil.transferOptionToUser1(
        writer1,
        parseTestToken('3'),
        2,
      );

      let baseAmount = parseEther('10');
      let amount = parseEther('10').add(baseAmount.mul(tax).div(1e4));
      await dai.mint(user1.address, amount);
      await dai.connect(user1).increaseAllowance(premiaOption.address, amount);

      baseAmount = parseTestToken('2');
      amount = baseAmount.add(baseAmount.mul(tax).div(1e4));

      await mintTestToken(user1, testToken, amount);
      await testToken.connect(user1).approve(premiaOption.address, amount);

      await premiaOption
        .connect(user1)
        .setApprovalForAll(p.premiaOptionBatch.address, true);

      await p.premiaOptionBatch
        .connect(user1)
        .batchExerciseOption(
          premiaOption.address,
          [1, 2],
          [parseTestToken('1'), parseTestToken('2')],
        );

      const optionBalance1 = await premiaOption.balanceOf(user1.address, 1);
      const optionBalance2 = await premiaOption.balanceOf(user1.address, 2);
      const daiBalance = await dai.balanceOf(user1.address);
      const testTokenBalance = await testToken.balanceOf(user1.address);

      expect(optionBalance1).to.eq(parseTestToken('1'));
      expect(optionBalance2).to.eq(parseTestToken('1'));
      expect(daiBalance).to.eq(parseEther('20'));
      expect(testTokenBalance).to.eq(parseTestToken('1'));
    });

    it('should fail exerciseOptionFrom if not approved', async () => {
      const amount = parseTestToken('2');
      await optionTestUtil.addTestTokenAndWriteOptions(amount, false);
      await optionTestUtil.transferOptionToUser1(writer1, amount);

      const amountTotal = amount.add(amount.mul(tax).div(1e4));

      await mintTestToken(user1, testToken, amountTotal);
      await testToken.connect(user1).approve(premiaOption.address, amountTotal);

      await expect(
        premiaOption
          .connect(writer2)
          .exerciseOptionFrom(user1.address, 1, amount),
      ).to.be.revertedWith('Not approved');
    });

    it('should successfully exerciseOptionFrom', async () => {
      const amount = parseTestToken('2');
      await optionTestUtil.addTestTokenAndWriteOptions(amount, false);
      await optionTestUtil.transferOptionToUser1(writer1, amount);

      const amountTotal = amount.add(amount.mul(tax).div(1e4));

      await mintTestToken(user1, testToken, amountTotal);
      await testToken.connect(user1).approve(premiaOption.address, amountTotal);

      await premiaOption
        .connect(user1)
        .setApprovalForAll(writer2.address, true);
      await premiaOption
        .connect(writer2)
        .exerciseOptionFrom(user1.address, 1, amount);

      expect(await premiaOption.balanceOf(user1.address, 1)).to.eq(0);
      expect(await dai.balanceOf(user1.address)).to.eq(parseEther('20'));
      expect(await testToken.balanceOf(premiaOption.address)).to.eq(
        parseTestToken('2'),
      );
    });
  });

  describe('withdraw', () => {
    it('should fail withdrawing if option not expired', async () => {
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('2'),
        parseTestToken('1'),
      );
      await expect(premiaOption.connect(writer1).withdraw(1)).to.revertedWith(
        'Not expired',
      );
    });

    it('should fail withdrawing from non-writer if option is expired', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1);
      await setTimestampPostExpiration();
      await expect(premiaOption.connect(user1).withdraw(1)).to.revertedWith(
        'No option to claim',
      );
    });

    it('should successfully allow writer withdrawal of 2 testToken if 0/2 call option exercised', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));
      await setTimestampPostExpiration();

      let testTokenBalance = await testToken.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      testTokenBalance = await testToken.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(testTokenBalance).to.eq(parseTestToken('2'));
      expect(daiBalance).to.eq(0);
    });

    it('should successfully allow writer withdrawal of 1 testToken and 10 dai if 1/2 call option exercised', async () => {
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('2'),
        parseTestToken('1'),
      );
      await setTimestampPostExpiration();

      let testTokenBalance = await testToken.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      testTokenBalance = await testToken.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(testTokenBalance).to.eq(parseTestToken('1'));
      expect(daiBalance).to.eq(parseEther('10'));
    });

    it('should successfully allow writer withdrawal of 20 dai if 2/2 call option exercised', async () => {
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('2'),
        parseTestToken('2'),
      );
      await setTimestampPostExpiration();

      let testTokenBalance = await testToken.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      testTokenBalance = await testToken.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(parseEther('20'));
    });

    it('should successfully allow writer withdrawal of 20 dai if 0/2 put option exercised', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        false,
      );
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));
      await setTimestampPostExpiration();

      let testTokenBalance = await testToken.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      testTokenBalance = await testToken.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(parseEther('20'));
    });

    it('should successfully allow writer withdrawal of 1 testToken and 10 dai if 1/2 put option exercised', async () => {
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        false,
        parseTestToken('2'),
        parseTestToken('1'),
      );
      await setTimestampPostExpiration();

      let testTokenBalance = await testToken.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      testTokenBalance = await testToken.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(testTokenBalance).to.eq(parseTestToken('1'));
      expect(daiBalance).to.eq(parseEther('10'));
    });

    it('should successfully allow writer withdrawal of 2 testToken if 2/2 put option exercised', async () => {
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        false,
        parseTestToken('2'),
        parseTestToken('2'),
      );
      await setTimestampPostExpiration();

      let testTokenBalance = await testToken.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption.connect(writer1).withdraw(1);

      testTokenBalance = await testToken.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(testTokenBalance).to.eq(parseTestToken('2'));
      expect(daiBalance).to.eq(0);
    });

    it('should withdraw 0.5 testToken and 5 dai if 1/2 option exercised and 2 different writers', async () => {
      await optionTestUtil.addTestToken();

      await optionTestUtil.mintAndWriteOption(writer1, parseTestToken('1'));
      await optionTestUtil.mintAndWriteOption(writer2, parseTestToken('1'));

      await optionTestUtil.transferOptionToUser1(writer1);
      await optionTestUtil.transferOptionToUser1(writer2);

      await optionTestUtil.exerciseOption(true, parseTestToken('1'));
      await setTimestampPostExpiration();

      await premiaOption.connect(writer1).withdraw(1);
      await premiaOption.connect(writer2).withdraw(1);

      const writer1TestToken = await testToken.balanceOf(writer1.address);
      const writer1Dai = await dai.balanceOf(writer1.address);

      const writer2TestToken = await testToken.balanceOf(writer2.address);
      const writer2Dai = await dai.balanceOf(writer2.address);

      expect(writer1TestToken).to.eq(parseTestToken('0.5'));
      expect(writer1Dai).to.eq(parseEther('5'));

      expect(writer2TestToken).to.eq(parseTestToken('0.5'));
      expect(writer2Dai).to.eq(parseEther('5'));
    });

    it('should withdraw 1 testToken, if 1/2 call exercised and 1 withdrawPreExpiration', async () => {
      await optionTestUtil.addTestToken();
      await optionTestUtil.mintAndWriteOption(writer1, parseTestToken('1'));
      await optionTestUtil.mintAndWriteOption(writer2, parseTestToken('1'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('1'));
      await optionTestUtil.transferOptionToUser1(writer2, parseTestToken('1'));
      await optionTestUtil.exerciseOption(true, parseTestToken('1'));

      await premiaOption
        .connect(writer2)
        .withdrawPreExpiration(1, parseTestToken('1'));

      await setTimestampPostExpiration();

      await premiaOption.connect(writer1).withdraw(1);

      const daiBalance = await dai.balanceOf(writer1.address);
      const testTokenBalance = await testToken.balanceOf(writer1.address);

      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);

      expect(daiBalance).to.eq(0);
      expect(testTokenBalance).to.eq(parseTestToken('1'));
      expect(nbWritten).to.eq(0);
    });

    it('should withdraw 10 dai, if 1/2 put exercised and 1 withdrawPreExpiration', async () => {
      await optionTestUtil.addTestToken();
      await optionTestUtil.mintAndWriteOption(
        writer1,
        parseTestToken('1'),
        false,
      );
      await optionTestUtil.mintAndWriteOption(
        writer2,
        parseTestToken('1'),
        false,
      );
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('1'));
      await optionTestUtil.transferOptionToUser1(writer2, parseTestToken('1'));
      await optionTestUtil.exerciseOption(false, parseTestToken('1'));

      await premiaOption
        .connect(writer2)
        .withdrawPreExpiration(1, parseTestToken('1'));

      await setTimestampPostExpiration();

      await premiaOption.connect(writer1).withdraw(1);

      const daiBalance = await dai.balanceOf(writer1.address);
      const testTokenBalance = await testToken.balanceOf(writer1.address);

      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);

      expect(daiBalance).to.eq(parseEther('10'));
      expect(testTokenBalance).to.eq(0);
      expect(nbWritten).to.eq(0);
    });

    it('should successfully batchWithdraw', async () => {
      await optionTestUtil.addTestToken();
      await optionTestUtil.mintAndWriteOption(writer1, parseTestToken('1'));
      await optionTestUtil.mintAndWriteOption(writer2, parseTestToken('1'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('1'));
      await optionTestUtil.transferOptionToUser1(writer2, parseTestToken('1'));
      await optionTestUtil.exerciseOption(true, parseTestToken('1'));

      await premiaOption
        .connect(writer2)
        .withdrawPreExpiration(1, parseTestToken('1'));

      await optionTestUtil.mintAndWriteOption(
        writer1,
        parseTestToken('1'),
        false,
      );
      await optionTestUtil.mintAndWriteOption(
        writer2,
        parseTestToken('1'),
        false,
      );
      await optionTestUtil.transferOptionToUser1(
        writer1,
        parseTestToken('1'),
        2,
      );
      await optionTestUtil.transferOptionToUser1(
        writer2,
        parseTestToken('1'),
        2,
      );
      await optionTestUtil.exerciseOption(
        false,
        parseTestToken('1'),
        undefined,
        2,
      );

      await premiaOption
        .connect(writer2)
        .withdrawPreExpiration(2, parseTestToken('1'));

      await setTimestampPostExpiration();

      await premiaOption
        .connect(writer1)
        .setApprovalForAll(p.premiaOptionBatch.address, true);
      await p.premiaOptionBatch
        .connect(writer1)
        .batchWithdraw(premiaOption.address, [1, 2]);

      const daiBalance = await dai.balanceOf(writer1.address);
      const testTokenBalance = await testToken.balanceOf(writer1.address);
      const nbWritten1 = await premiaOption.nbWritten(writer1.address, 1);
      const nbWritten2 = await premiaOption.nbWritten(writer1.address, 2);

      expect(daiBalance).to.eq(parseEther('10'));
      expect(testTokenBalance).to.eq(parseTestToken('1'));
      expect(nbWritten1).to.eq(0);
      expect(nbWritten2).to.eq(0);
    });

    it('should fail withdrawFrom if not approved', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));
      await setTimestampPostExpiration();

      let testTokenBalance = await testToken.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await expect(
        premiaOption.connect(writer2).withdrawFrom(writer1.address, 1),
      ).to.be.revertedWith('Not approved');
    });

    it('should successfully withdrawFrom', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));
      await setTimestampPostExpiration();

      let testTokenBalance = await testToken.balanceOf(writer1.address);
      let daiBalance = await dai.balanceOf(writer1.address);
      expect(testTokenBalance).to.eq(0);
      expect(daiBalance).to.eq(0);

      await premiaOption
        .connect(writer1)
        .setApprovalForAll(writer2.address, true);
      await premiaOption.connect(writer2).withdrawFrom(writer1.address, 1);

      testTokenBalance = await testToken.balanceOf(writer1.address);
      daiBalance = await dai.balanceOf(writer1.address);

      expect(testTokenBalance).to.eq(parseTestToken('2'));
      expect(daiBalance).to.eq(0);
    });
  });

  describe('withdrawPreExpiration', () => {
    it('should fail withdrawing if option is expired', async () => {
      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('2'),
        parseTestToken('1'),
      );
      await setTimestampPostExpiration();
      await expect(
        premiaOption.withdrawPreExpiration(1, parseTestToken('1')),
      ).to.revertedWith('Expired');
    });

    it('should fail withdrawing from non-writer if option is not expired', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1);
      await expect(
        premiaOption
          .connect(user1)
          .withdrawPreExpiration(1, parseTestToken('1')),
      ).to.revertedWith('Not enough claims');
    });

    it('should fail withdrawing if no unclaimed exercised options', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));

      await expect(
        premiaOption
          .connect(writer1)
          .withdrawPreExpiration(1, parseTestToken('2')),
      ).to.revertedWith('Not enough claimable');
    });

    it('should fail withdrawing if not enough unclaimed exercised options', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));
      await optionTestUtil.exerciseOption(true, parseTestToken('1'));

      await expect(
        premiaOption
          .connect(writer1)
          .withdrawPreExpiration(1, parseTestToken('2')),
      ).to.revertedWith('Not enough claimable');
    });

    it('should successfully withdraw 10 dai for withdrawPreExpiration of call option exercised', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));
      await optionTestUtil.exerciseOption(true, parseTestToken('1'));

      await premiaOption
        .connect(writer1)
        .withdrawPreExpiration(1, parseTestToken('1'));

      const daiBalance = await dai.balanceOf(writer1.address);
      const testTokenBalance = await testToken.balanceOf(writer1.address);

      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);

      expect(daiBalance).to.eq(parseEther('10'));
      expect(testTokenBalance).to.eq(0);
      expect(nbWritten).to.eq(parseTestToken('1'));
    });

    it('should successfully withdraw 1 testToken for withdrawPreExpiration of put option exercised', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        false,
      );
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));
      await optionTestUtil.exerciseOption(false, parseTestToken('1'));

      await premiaOption
        .connect(writer1)
        .withdrawPreExpiration(1, parseTestToken('1'));

      const daiBalance = await dai.balanceOf(writer1.address);
      const testTokenBalance = await testToken.balanceOf(writer1.address);

      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);

      expect(daiBalance).to.eq(0);
      expect(testTokenBalance).to.eq(parseTestToken('1'));
      expect(nbWritten).to.eq(parseTestToken('1'));
    });

    it('should successfully batchWithdrawPreExpiration', async () => {
      await optionTestUtil.addTestToken();
      await optionTestUtil.mintAndWriteOption(
        writer1,
        parseTestToken('3'),
        true,
      );
      await optionTestUtil.mintAndWriteOption(
        writer1,
        parseTestToken('3'),
        false,
      );

      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('3'));
      await optionTestUtil.transferOptionToUser1(
        writer1,
        parseTestToken('3'),
        2,
      );
      await optionTestUtil.exerciseOption(true, parseTestToken('2'));
      await optionTestUtil.exerciseOption(
        false,
        parseTestToken('1'),
        undefined,
        2,
      );

      await premiaOption
        .connect(writer1)
        .setApprovalForAll(p.premiaOptionBatch.address, true);
      await p.premiaOptionBatch
        .connect(writer1)
        .batchWithdrawPreExpiration(
          premiaOption.address,
          [1, 2],
          [parseTestToken('2'), parseTestToken('1')],
        );

      const daiBalance = await dai.balanceOf(writer1.address);
      const testTokenBalance = await testToken.balanceOf(writer1.address);

      const nbWritten1 = await premiaOption.nbWritten(writer1.address, 1);
      const nbWritten2 = await premiaOption.nbWritten(writer1.address, 2);

      expect(daiBalance).to.eq(parseEther('20'));
      expect(testTokenBalance).to.eq(parseTestToken('1'));
      expect(nbWritten1).to.eq(parseTestToken('1'));
      expect(nbWritten2).to.eq(parseTestToken('2'));
    });

    it('should fail withdrawPreExpirationFrom if not approved', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));
      await optionTestUtil.exerciseOption(true, parseTestToken('1'));

      await expect(
        premiaOption
          .connect(writer2)
          .withdrawPreExpirationFrom(writer1.address, 1, parseTestToken('1')),
      ).to.be.revertedWith('Not approved');
    });

    it('should successfully withdrawPreExpirationFrom', async () => {
      await optionTestUtil.addTestTokenAndWriteOptions(parseTestToken('2'));
      await optionTestUtil.transferOptionToUser1(writer1, parseTestToken('2'));
      await optionTestUtil.exerciseOption(true, parseTestToken('1'));

      await premiaOption
        .connect(writer1)
        .setApprovalForAll(writer2.address, true);
      await premiaOption
        .connect(writer2)
        .withdrawPreExpirationFrom(writer1.address, 1, parseTestToken('1'));

      const daiBalance = await dai.balanceOf(writer1.address);
      const testTokenBalance = await testToken.balanceOf(writer1.address);

      const nbWritten = await premiaOption.nbWritten(writer1.address, 1);

      expect(daiBalance).to.eq(parseEther('10'));
      expect(testTokenBalance).to.eq(0);
      expect(nbWritten).to.eq(parseTestToken('1'));
    });
  });

  describe('fees', () => {
    it('should calculate total fee correctly without discount', async () => {
      const fee = await p.feeCalculator.getFeeAmount(
        writer1.address,
        parseTestToken('2'),
        0,
      );

      expect(fee).to.eq(parseTestToken('0.02'));
    });

    it('should correctly calculate total fee with staking discount', async () => {
      await premiaFeeDiscount.setDiscount(2000);
      const fee = await p.feeCalculator.getFeeAmount(
        writer1.address,
        parseTestToken('2'),
        0,
      );

      expect(fee).to.eq(parseTestToken('0.016'));
    });

    it('should correctly give a 30% discount from premia staking', async () => {
      await premiaFeeDiscount.setDiscount(3000);

      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('2'),
        parseTestToken('2'),
      );

      const user1Options = await premiaOption.balanceOf(writer1.address, 1);
      const user1Dai = await dai.balanceOf(user1.address);

      expect(user1Options).to.eq(0);
      expect(user1Dai).to.eq(
        BigNumber.from(parseEther('0.06')), // Expect 30% of the 1% tax of 2 options exercised at strike price of 10 DAI
      );
    });

    it('should correctly give a 30% discount from premia staking', async () => {
      await premiaFeeDiscount.setDiscount(3000);

      await optionTestUtil.addTestTokenAndWriteOptionsAndExercise(
        true,
        parseTestToken('2'),
        parseTestToken('2'),
        writer2.address,
      );

      const user1Options = await premiaOption.balanceOf(writer1.address, 1);
      const user1Dai = await dai.balanceOf(user1.address);

      expect(user1Options).to.eq(0);
      expect(user1Dai).to.eq(
        BigNumber.from(parseEther('0.06')), // Expect 30% of the 1% tax of 2 options exercised at strike price of 10 DAI
      );
    });
  });

  describe('flashLoan', () => {
    it('should revert if loan not paid back', async () => {
      const flashLoanFactory = new TestFlashLoan__factory(writer1);

      const flashLoan = await flashLoanFactory.deploy();
      await flashLoan.setMode(2);

      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        true,
        user1.address,
      );

      let testTokenBalance = await testToken.balanceOf(premiaOption.address);

      expect(testTokenBalance).to.eq(parseTestToken('2'));

      await expect(
        premiaOption.flashLoan(
          testToken.address,
          parseTestToken('2'),
          flashLoan.address,
        ),
      ).to.be.revertedWith('Failed to pay back');
    });

    it('should revert if loan paid back without fee', async () => {
      const flashLoanFactory = new TestFlashLoan__factory(writer1);

      const flashLoan = await flashLoanFactory.deploy();
      await flashLoan.setMode(1);

      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        true,
        user1.address,
      );

      let testTokenBalance = await testToken.balanceOf(premiaOption.address);

      expect(testTokenBalance).to.eq(parseTestToken('2'));

      await expect(
        premiaOption.flashLoan(
          testToken.address,
          parseTestToken('2'),
          flashLoan.address,
        ),
      ).to.be.revertedWith('Failed to pay back');
    });

    it('should successfully complete flashLoan if paid back with fee', async () => {
      await p.feeCalculator.setWriteFee(0);
      const flashLoanFactory = new TestFlashLoan__factory(writer1);

      const flashLoan = await flashLoanFactory.deploy();
      await flashLoan.setMode(0);

      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        true,
        user1.address,
      );

      await mintTestToken(admin, testToken, parseTestToken('0.004'));
      await testToken.transfer(flashLoan.address, parseTestToken('0.004'));

      let testTokenBalance = await testToken.balanceOf(premiaOption.address);
      expect(testTokenBalance).to.eq(parseTestToken('2'));

      await premiaOption.flashLoan(
        testToken.address,
        parseTestToken('2'),
        flashLoan.address,
      );

      testTokenBalance = await testToken.balanceOf(premiaOption.address);
      expect(testTokenBalance).to.eq(parseTestToken('2'));

      const testTokenBalanceFeeRecipient = await testToken.balanceOf(
        feeRecipient.address,
      );
      expect(testTokenBalanceFeeRecipient).to.eq(parseTestToken('0.004'));
    });

    it('should successfully complete flashLoan if paid back without fee and user on fee whitelist', async () => {
      await p.feeCalculator.setWriteFee(0);
      const flashLoanFactory = new TestFlashLoan__factory(writer1);

      const flashLoan = await flashLoanFactory.deploy();
      await flashLoan.setMode(1);
      await p.feeCalculator.addWhitelisted([writer1.address]);

      await optionTestUtil.addTestTokenAndWriteOptions(
        parseTestToken('2'),
        true,
        user1.address,
      );

      let testTokenBalance = await testToken.balanceOf(premiaOption.address);
      expect(testTokenBalance).to.eq(parseTestToken('2'));

      await premiaOption
        .connect(writer1)
        .flashLoan(testToken.address, parseTestToken('2'), flashLoan.address);

      testTokenBalance = await testToken.balanceOf(premiaOption.address);
      expect(testTokenBalance).to.eq(parseTestToken('2'));

      const testTokenBalanceFeeRecipient = await testToken.balanceOf(
        feeRecipient.address,
      );
      expect(testTokenBalanceFeeRecipient).to.eq(0);
    });
  });

  describe('flashExercise', () => {
    beforeEach(async () => {
      // This test only works when we use WETH (Has been tested directly on testnet with wbtc)
      if (!TEST_USE_WETH) return;

      uniswap = await createUniswap(admin, p.premia, dai, weth);
      await premiaOption.setWhitelistedUniswapRouters([uniswap.router.address]);
    });

    it('should successfully flash exercise if option in the money', async () => {
      // This test only works when we use WETH (Has been tested directly on testnet with wbtc)
      if (!TEST_USE_WETH) return;

      // 1 ETH = 12 DAI
      await uniswap.dai.mint(uniswap.daiWeth.address, parseEther('1200'));
      await uniswap.weth.deposit({ value: parseEther('100') });
      await uniswap.weth.transfer(uniswap.daiWeth.address, parseEther('100'));
      await uniswap.daiWeth.mint(admin.address);

      await optionTestUtil.addTestTokenAndWriteOptions(parseEther('2'), true);
      await optionTestUtil.transferOptionToUser1(writer1, parseEther('2'));

      await premiaOption
        .connect(user1)
        .flashExerciseOption(
          1,
          parseEther('1'),
          uniswap.router.address,
          parseEther('100000'),
          testToken.address === weth.address
            ? [weth.address, dai.address]
            : [testToken.address, weth.address, dai.address],
        );

      const user1Weth = await uniswap.weth.balanceOf(user1.address);
      expect(
        user1Weth.gt(parseEther('0.148')) && user1Weth.lt(parseEther('0.149')),
      ).to.be.true;
      expect(await uniswap.dai.balanceOf(premiaOption.address)).to.eq(
        parseEther('10'),
      );
      expect(await premiaOption.balanceOf(user1.address, 1)).to.eq(
        parseEther('1'),
      );
    });

    it('should fail flash exercise if option not in the money', async () => {
      // This test only works when we use WETH (Has been tested directly on testnet with wbtc)
      if (!TEST_USE_WETH) return;

      // 1 ETH = 8 DAI
      await uniswap.dai.mint(uniswap.daiWeth.address, parseEther('800'));
      await uniswap.weth.deposit({ value: parseEther('100') });
      await uniswap.weth.transfer(uniswap.daiWeth.address, parseEther('100'));
      await uniswap.daiWeth.mint(admin.address);

      await optionTestUtil.addTestTokenAndWriteOptions(parseEther('2'), true);
      await optionTestUtil.transferOptionToUser1(writer1, parseEther('2'));

      await expect(
        premiaOption
          .connect(user1)
          .flashExerciseOption(
            1,
            parseEther('1'),
            uniswap.router.address,
            parseEther('100000'),
            testToken.address === weth.address
              ? [weth.address, dai.address]
              : [testToken.address, weth.address, dai.address],
          ),
      ).to.be.revertedWith('UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
    });

    it('should fail flashExerciseFrom if not approved', async () => {
      // This test only works when we use WETH (Has been tested directly on testnet with wbtc)
      if (!TEST_USE_WETH) return;

      // 1 ETH = 12 DAI
      await uniswap.dai.mint(uniswap.daiWeth.address, parseEther('1200'));
      await uniswap.weth.deposit({ value: parseEther('100') });
      await uniswap.weth.transfer(uniswap.daiWeth.address, parseEther('100'));
      await uniswap.daiWeth.mint(admin.address);

      await optionTestUtil.addTestTokenAndWriteOptions(parseEther('2'), true);
      await optionTestUtil.transferOptionToUser1(writer1, parseEther('2'));

      await expect(
        premiaOption
          .connect(writer2)
          .flashExerciseOptionFrom(
            user1.address,
            1,
            parseEther('1'),
            uniswap.router.address,
            parseEther('100000'),
            testToken.address === weth.address
              ? [weth.address, dai.address]
              : [testToken.address, weth.address, dai.address],
          ),
      ).to.be.revertedWith('Not approved');
    });

    it('should successfully flashExerciseFrom', async () => {
      // This test only works when we use WETH (Has been tested directly on testnet with wbtc)
      if (!TEST_USE_WETH) return;

      // 1 ETH = 12 DAI
      await uniswap.dai.mint(uniswap.daiWeth.address, parseEther('1200'));
      await uniswap.weth.deposit({ value: parseEther('100') });
      await uniswap.weth.transfer(uniswap.daiWeth.address, parseEther('100'));
      await uniswap.daiWeth.mint(admin.address);

      await optionTestUtil.addTestTokenAndWriteOptions(parseEther('2'), true);
      await optionTestUtil.transferOptionToUser1(writer1, parseEther('2'));

      await premiaOption
        .connect(user1)
        .setApprovalForAll(writer2.address, true);
      await premiaOption
        .connect(writer2)
        .flashExerciseOptionFrom(
          user1.address,
          1,
          parseEther('1'),
          uniswap.router.address,
          parseEther('100000'),
          testToken.address === weth.address
            ? [weth.address, dai.address]
            : [testToken.address, weth.address, dai.address],
        );

      const user1Weth = await uniswap.weth.balanceOf(user1.address);
      expect(
        user1Weth.gt(parseEther('0.148')) && user1Weth.lt(parseEther('0.149')),
      ).to.be.true;
      expect(await uniswap.dai.balanceOf(premiaOption.address)).to.eq(
        parseEther('10'),
      );
      expect(await premiaOption.balanceOf(user1.address, 1)).to.eq(
        parseTestToken('1'),
      );
    });
  });
});
