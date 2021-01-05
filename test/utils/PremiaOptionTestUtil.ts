import { PremiaOption, TestErc20 } from '../../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumberish, utils } from 'ethers';
import { ONE_WEEK, ZERO_ADDRESS } from './constants';

interface WriteOptionArgs {
  address?: string;
  expiration?: number;
  strikePrice?: BigNumberish;
  isCall?: boolean;
  contractAmount?: number;
  referrer?: string;
}

interface PremiaOptionTestUtilProps {
  eth: TestErc20;
  dai: TestErc20;
  premiaOption: PremiaOption;
  admin: SignerWithAddress;
  writer1: SignerWithAddress;
  writer2: SignerWithAddress;
  user1: SignerWithAddress;
  treasury: SignerWithAddress;
  tax: number;
}

export class PremiaOptionTestUtil {
  eth: TestErc20;
  dai: TestErc20;
  premiaOption: PremiaOption;
  admin: SignerWithAddress;
  writer1: SignerWithAddress;
  writer2: SignerWithAddress;
  user1: SignerWithAddress;
  treasury: SignerWithAddress;
  tax: number;

  constructor(props: PremiaOptionTestUtilProps) {
    this.eth = props.eth;
    this.dai = props.dai;
    this.premiaOption = props.premiaOption;
    this.admin = props.admin;
    this.writer1 = props.writer1;
    this.writer2 = props.writer2;
    this.user1 = props.user1;
    this.treasury = props.treasury;
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
      address: this.eth.address,
      expiration: this.getNextExpiration(),
      strikePrice: utils.parseEther('10'),
      isCall: true,
      contractAmount: 1,
    };
  }

  async addEth() {
    return this.premiaOption.setToken(
      this.eth.address,
      utils.parseEther('1'),
      utils.parseEther('10'),
      false,
    );
  }

  async writeOption(user: SignerWithAddress, args?: WriteOptionArgs) {
    const defaults = this.getOptionDefaults();

    return this.premiaOption.connect(user).writeOption(
      {
        token: args?.address ?? defaults.address,
        expiration: args?.expiration ?? defaults.expiration,
        strikePrice: args?.strikePrice ?? defaults.strikePrice,
        isCall: args?.isCall == undefined ? defaults.isCall : args.isCall,
        contractAmount:
          args?.contractAmount == undefined
            ? defaults.contractAmount
            : args?.contractAmount,
      },
      args?.referrer ?? ZERO_ADDRESS,
    );
  }

  async mintAndWriteOption(
    user: SignerWithAddress,
    contractAmount: number,
    isCall = true,
    referrer?: string,
  ) {
    if (isCall) {
      const amount = utils
        .parseEther(contractAmount.toString())
        .mul(1e5 + this.tax * 1e5)
        .div(1e5);
      await this.eth.mint(user.address, amount.toString());
      await this.eth
        .connect(user)
        .increaseAllowance(
          this.premiaOption.address,
          utils.parseEther(amount.toString()),
        );
    } else {
      const amount = utils
        .parseEther('10')
        .mul(contractAmount)
        .mul(1e5 + this.tax * 1e5)
        .div(1e5);
      await this.dai.mint(user.address, amount);
      await this.dai
        .connect(user)
        .increaseAllowance(
          this.premiaOption.address,
          utils.parseEther(amount.toString()),
        );
    }

    await this.writeOption(user, { contractAmount, isCall, referrer });
  }

  async addEthAndWriteOptions(
    contractAmount: number,
    isCall = true,
    referrer?: string,
  ) {
    await this.addEth();
    await this.mintAndWriteOption(
      this.writer1,
      contractAmount,
      isCall,
      referrer,
    );
  }

  async transferOptionToUser1(
    from: SignerWithAddress,
    amount?: number,
    optionId?: number,
  ) {
    await this.premiaOption
      .connect(from)
      .safeTransferFrom(
        from.address,
        this.user1.address,
        optionId ?? 1,
        amount ?? 1,
        '0x00',
      );
  }

  async exerciseOption(
    isCall: boolean,
    amountToExercise: number,
    referrer?: string,
    optionId?: number,
  ) {
    if (isCall) {
      const amount = amountToExercise * 10 * (1 + this.tax);
      await this.dai.mint(
        this.user1.address,
        utils.parseEther(amount.toString()),
      );
      await this.dai
        .connect(this.user1)
        .increaseAllowance(
          this.premiaOption.address,
          utils.parseEther(amount.toString()),
        );
    } else {
      const amount = amountToExercise * (1 + this.tax);

      await this.eth.mint(
        this.user1.address,
        utils.parseEther(amount.toString()),
      );
      await this.eth
        .connect(this.user1)
        .increaseAllowance(
          this.premiaOption.address,
          utils.parseEther(amount.toString()),
        );
    }

    return this.premiaOption
      .connect(this.user1)
      .exerciseOption(
        optionId ?? 1,
        amountToExercise,
        referrer ?? ZERO_ADDRESS,
      );
  }

  async addEthAndWriteOptionsAndExercise(
    isCall: boolean,
    amountToWrite: number,
    amountToExercise: number,
    referrer?: string,
  ) {
    await this.addEthAndWriteOptions(amountToWrite, isCall);
    await this.transferOptionToUser1(this.writer1, amountToWrite);
    await this.exerciseOption(isCall, amountToExercise, referrer);
  }
}
