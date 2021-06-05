import { Option, TestErc20, WETH9 } from '../../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumber, BigNumberish } from 'ethers';
import { ONE_WEEK, TEST_TOKEN_DECIMALS } from './constants';
import { formatUnits, parseEther } from 'ethers/lib/utils';
import { mintTestToken, parseTestToken } from './token';

interface WriteOptionArgs {
  address?: string;
  expiration?: number;
  strikePrice?: BigNumberish;
  isCall?: boolean;
  amount?: BigNumber;
  referrer?: string;
}

interface OptionTestUtilProps {
  testToken: WETH9 | TestErc20;
  dai: TestErc20;
  option: Option;
  admin: SignerWithAddress;
  writer1: SignerWithAddress;
  writer2: SignerWithAddress;
  user1: SignerWithAddress;
  feeRecipient: SignerWithAddress;
  tax: number;
}

export class OptionTestUtil {
  testToken: WETH9 | TestErc20;
  dai: TestErc20;
  option: Option;
  admin: SignerWithAddress;
  writer1: SignerWithAddress;
  writer2: SignerWithAddress;
  user1: SignerWithAddress;
  feeRecipient: SignerWithAddress;
  tax: number;

  constructor(props: OptionTestUtilProps) {
    this.testToken = props.testToken;
    this.dai = props.dai;
    this.option = props.option;
    this.admin = props.admin;
    this.writer1 = props.writer1;
    this.writer2 = props.writer2;
    this.user1 = props.user1;
    this.feeRecipient = props.feeRecipient;
    this.tax = props.tax;
  }

  getNextExpiration() {
    const now = new Date();
    const baseExpiration = 172799; // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
    return (
      ONE_WEEK *
        (Math.floor((now.getTime() / 1000 - baseExpiration) / ONE_WEEK) + 1) +
      baseExpiration
    );
  }

  getOptionDefaults() {
    return {
      token: this.testToken.address,
      expiration: this.getNextExpiration(),
      strikePrice: parseEther('10'),
      isCall: true,
      amount: parseTestToken('1'),
    };
  }

  async addTestToken() {
    return this.option.setTokensWhitelisted([this.testToken.address], true);
  }

  async writeOption(user: SignerWithAddress, args?: WriteOptionArgs) {
    const defaults = this.getOptionDefaults();

    return this.option.connect(user).writeOption({
      token: args?.address ?? defaults.token,
      expiration: args?.expiration ?? defaults.expiration,
      strikePrice: args?.strikePrice ?? defaults.strikePrice,
      isCall: args?.isCall == undefined ? defaults.isCall : args.isCall,
      amount: args?.amount == undefined ? defaults.amount : args?.amount,
    });
  }

  async mintAndWriteOption(
    user: SignerWithAddress,
    amount: BigNumber,
    isCall = true,
    referrer?: string,
  ) {
    if (isCall) {
      const amountWithFee = amount.add(amount.mul(this.tax).div(1e4));
      await mintTestToken(user, this.testToken, amountWithFee);
      await this.testToken
        .connect(user)
        .approve(this.option.address, amountWithFee);
    } else {
      const baseAmount = parseEther(
        (Number(formatUnits(amount, TEST_TOKEN_DECIMALS)) * 10).toString(),
      );
      const amountWithFee = baseAmount.add(baseAmount.mul(this.tax).div(1e4));
      await this.dai.mint(user.address, amountWithFee);
      await this.dai
        .connect(user)
        .increaseAllowance(this.option.address, amountWithFee);
    }

    await this.writeOption(user, { amount, isCall, referrer });
    // const tx = await this.writeOption(user, { amount, isCall, referrer });
    // console.log(tx.gasLimit.toString());
  }

  async addTestTokenAndWriteOptions(
    amount: BigNumber,
    isCall = true,
    referrer?: string,
  ) {
    await this.addTestToken();
    await this.mintAndWriteOption(this.writer1, amount, isCall, referrer);
  }

  async transferOptionToUser1(
    from: SignerWithAddress,
    amount?: BigNumber,
    optionId?: number,
  ) {
    await this.option
      .connect(from)
      .safeTransferFrom(
        from.address,
        this.user1.address,
        optionId ?? 1,
        amount ?? parseTestToken('1'),
        '0x00',
      );
  }

  async exerciseOption(
    isCall: boolean,
    amountToExercise: BigNumber,
    referrer?: string,
    optionId?: number,
  ) {
    if (isCall) {
      const baseAmount = parseEther(
        formatUnits(amountToExercise.mul(10), TEST_TOKEN_DECIMALS),
      );
      const amount = baseAmount.add(baseAmount.mul(this.tax).div(1e4));
      await this.dai.mint(this.user1.address, amount);
      await this.dai
        .connect(this.user1)
        .increaseAllowance(this.option.address, amount);
    } else {
      const amount = amountToExercise.add(
        amountToExercise.mul(this.tax).div(1e4),
      );

      await mintTestToken(this.user1, this.testToken, amount);
      await this.testToken
        .connect(this.user1)
        .approve(this.option.address, amount);
    }

    return this.option
      .connect(this.user1)
      .exerciseOption(optionId ?? 1, amountToExercise);
  }

  async addTestTokenAndWriteOptionsAndExercise(
    isCall: boolean,
    amountToWrite: BigNumber,
    amountToExercise: BigNumber,
    referrer?: string,
  ) {
    await this.addTestTokenAndWriteOptions(amountToWrite, isCall);
    await this.transferOptionToUser1(this.writer1, amountToWrite);
    await this.exerciseOption(isCall, amountToExercise, referrer);
  }
}
