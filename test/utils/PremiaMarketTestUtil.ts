import {
  TestErc20,
  TestPremiaMarket,
  TestPremiaOption,
  TestTokenSettingsCalculator__factory,
} from '../../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumber, BigNumberish, utils } from 'ethers';
import { IOrderCreated, IOrderCreateProps } from '../../types';

interface PremiaMarketTestUtilProps {
  eth: TestErc20;
  dai: TestErc20;
  premiaOption: TestPremiaOption;
  premiaMarket: TestPremiaMarket;
  admin: SignerWithAddress;
  writer1: SignerWithAddress;
  writer2: SignerWithAddress;
  user1: SignerWithAddress;
  treasury: SignerWithAddress;
}

export class PremiaMarketTestUtil {
  eth: TestErc20;
  dai: TestErc20;
  premiaOption: TestPremiaOption;
  premiaMarket: TestPremiaMarket;
  admin: SignerWithAddress;
  writer1: SignerWithAddress;
  writer2: SignerWithAddress;
  user1: SignerWithAddress;
  treasury: SignerWithAddress;

  constructor(props: PremiaMarketTestUtilProps) {
    this.eth = props.eth;
    this.dai = props.dai;
    this.premiaOption = props.premiaOption;
    this.premiaMarket = props.premiaMarket;
    this.admin = props.admin;
    this.writer1 = props.writer1;
    this.writer2 = props.writer2;
    this.user1 = props.user1;
    this.treasury = props.treasury;
  }

  isOrderSame(order: IOrderCreateProps, orderCreated: IOrderCreated) {
    return (
      order.maker === orderCreated.maker &&
      order.taker === orderCreated.taker &&
      order.side === orderCreated.side &&
      order.optionContract === orderCreated.optionContract &&
      BigNumber.from(order.pricePerUnit).eq(orderCreated.pricePerUnit) &&
      BigNumber.from(order.optionId).eq(orderCreated.optionId)
    );
  }
}
