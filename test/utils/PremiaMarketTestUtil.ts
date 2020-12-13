import {
  TestErc20,
  TestPremiaMarket,
  TestPremiaOption,
} from '../../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumber, BigNumberish } from 'ethers';
import { IOrderCreated, IOrderCreateProps } from '../../types';
import { ethers } from 'hardhat';

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

  getDefaultOrder(user: SignerWithAddress, isSell: boolean) {
    const newOrder: IOrderCreateProps = {
      maker: user.address,
      taker: '0x0000000000000000000000000000000000000000',
      side: Number(isSell),
      optionContract: this.premiaOption.address,
      pricePerUnit: ethers.utils.parseEther('1'),
      optionId: 1,
    };

    return newOrder;
  }

  async createOrder(user: SignerWithAddress, isSell = true) {
    const newOrder = this.getDefaultOrder(user, isSell);

    const tx = await this.premiaMarket.connect(user).createOrder(
      {
        ...newOrder,
        expirationTime: 0,
        salt: 0,
      },
      1,
    );

    const filter = this.premiaMarket.filters.OrderCreated(
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
    );
    const r = await this.premiaMarket.queryFilter(filter, tx.blockHash);

    const events = r.map((el) => (el.args as any) as IOrderCreated);
    const order = events.find((order) => this.isOrderSame(newOrder, order));

    if (!order) {
      throw new Error('Order not found in events');
    }

    return order;
  }

  convertOrderCreatedToOrder(orderCreated: IOrderCreated) {
    return {
      maker: orderCreated.maker,
      taker: orderCreated.taker,
      side: orderCreated.side,
      optionContract: orderCreated.optionContract,
      optionId: orderCreated.optionId,
      pricePerUnit: orderCreated.pricePerUnit,
      expirationTime: orderCreated.expirationTime,
      salt: orderCreated.salt,
    };
  }
}
