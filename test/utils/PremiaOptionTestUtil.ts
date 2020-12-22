import {
  TestErc20,
  TestPremiaOption,
  TestTokenSettingsCalculator__factory,
} from '../../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumberish, utils } from 'ethers';
import { ZERO_ADDRESS } from './constants';

interface WriteOptionArgs {
  address?: string;
  expiration?: number;
  strikePrice?: BigNumberish;
  isCall?: boolean;
  contractAmount?: number;
}

interface PremiaOptionTestUtilProps {
  eth: TestErc20;
  dai: TestErc20;
  premiaOption: TestPremiaOption;
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
  premiaOption: TestPremiaOption;
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

  getOptionDefaults() {
    return {
      address: this.eth.address,
      expiration: 777599,
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
    );
  }

  async addTokenSettingsCalculator() {
    const tokenSettingsCalculatorFactory = new TestTokenSettingsCalculator__factory(
      this.writer1,
    );
    const tokenSettingsCalculator = await tokenSettingsCalculatorFactory.deploy();
    await this.premiaOption.setTokenSettingsCalculator(
      tokenSettingsCalculator.address,
    );
  }

  async writeOption(user: SignerWithAddress, args?: WriteOptionArgs) {
    const defaults = this.getOptionDefaults();

    return this.premiaOption
      .connect(user)
      .writeOption(
        args?.address ?? defaults.address,
        args?.expiration ?? defaults.expiration,
        args?.strikePrice ?? defaults.strikePrice,
        args?.isCall == undefined ? defaults.isCall : args.isCall,
        args?.contractAmount == undefined
          ? defaults.contractAmount
          : args?.contractAmount,
        ZERO_ADDRESS,
      );
  }

  async mintAndWriteOption(
    user: SignerWithAddress,
    contractAmount: number,
    isCall = true,
  ) {
    if (isCall) {
      const amount = contractAmount * (1 + this.tax);
      await this.eth.connect(user).mint(utils.parseEther(amount.toString()));
      await this.eth
        .connect(user)
        .increaseAllowance(
          this.premiaOption.address,
          utils.parseEther(amount.toString()),
        );
    } else {
      const amount = 10 * contractAmount * (1 + this.tax);
      await this.dai.connect(user).mint(utils.parseEther(amount.toString()));
      await this.dai
        .connect(user)
        .increaseAllowance(
          this.premiaOption.address,
          utils.parseEther(amount.toString()),
        );
    }

    await this.writeOption(user, { contractAmount, isCall });
  }

  async addEthAndWriteOptions(contractAmount: number, isCall = true) {
    await this.addEth();
    await this.mintAndWriteOption(this.writer1, contractAmount, isCall);
  }

  async transferOptionToUser1(from: SignerWithAddress, amount?: number) {
    await this.premiaOption
      .connect(from)
      .safeTransferFrom(
        from.address,
        this.user1.address,
        1,
        amount ?? 1,
        '0x00',
      );
  }

  async exerciseOption(isCall: boolean, amountToExercise: number) {
    if (isCall) {
      const amount = amountToExercise * 10 * (1 + this.tax);
      await this.dai
        .connect(this.user1)
        .mint(utils.parseEther(amount.toString()));
      await this.dai
        .connect(this.user1)
        .increaseAllowance(
          this.premiaOption.address,
          utils.parseEther(amount.toString()),
        );
    } else {
      const amount = amountToExercise * (1 + this.tax);

      await this.eth
        .connect(this.user1)
        .mint(utils.parseEther(amount.toString()));
      await this.eth
        .connect(this.user1)
        .increaseAllowance(
          this.premiaOption.address,
          utils.parseEther(amount.toString()),
        );
    }

    return this.premiaOption
      .connect(this.user1)
      .exerciseOption(1, amountToExercise, ZERO_ADDRESS);
  }

  async addEthAndWriteOptionsAndExercise(
    isCall: boolean,
    amountToWrite: number,
    amountToExercise: number,
  ) {
    await this.addEthAndWriteOptions(amountToWrite, isCall);
    await this.transferOptionToUser1(this.writer1, amountToWrite);
    await this.exerciseOption(isCall, amountToExercise);
  }
}
