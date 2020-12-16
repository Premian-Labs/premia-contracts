import {
  TestErc20,
  TestPremiaMarket,
  TestPremiaOption,
} from '../../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumber } from 'ethers';
import { IOrderCreated, IOrderCreateProps } from '../../types';
import { ethers } from 'hardhat';
import { PremiaOptionTestUtil } from './PremiaOptionTestUtil';

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

interface OrderOptions {
  taker?: string;
  isBuy?: boolean;
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
  optionTestUtil: PremiaOptionTestUtil;

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

    this.optionTestUtil = new PremiaOptionTestUtil({
      eth: this.eth,
      dai: this.dai,
      premiaOption: this.premiaOption,
      writer1: this.writer1,
      writer2: this.writer2,
      user1: this.user1,
      treasury: this.treasury,
      tax: 0.01,
    });
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

  getDefaultOrder(user: SignerWithAddress, orderOptions?: OrderOptions) {
    const newOrder: IOrderCreateProps = {
      maker: user.address,
      taker:
        orderOptions?.taker ?? '0x0000000000000000000000000000000000000000',
      side: Number(!orderOptions?.isBuy),
      optionContract: this.premiaOption.address,
      pricePerUnit: ethers.utils.parseEther('1'),
      optionId: 1,
    };

    return newOrder;
  }

  async createOrder(user: SignerWithAddress, orderOptions?: OrderOptions) {
    const newOrder = this.getDefaultOrder(user, orderOptions);

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

  async setupOrder(
    maker: SignerWithAddress,
    taker: SignerWithAddress,
    orderOptions?: OrderOptions,
  ) {
    let buyer: SignerWithAddress;
    let seller: SignerWithAddress;
    if (orderOptions?.isBuy) {
      buyer = maker;
      seller = taker;
    } else {
      buyer = taker;
      seller = maker;
    }

    await this.optionTestUtil.mintAndWriteOption(seller, 1);

    await this.eth.connect(buyer).mint(ethers.utils.parseEther('1.015'));
    await this.eth
      .connect(buyer)
      .increaseAllowance(
        this.premiaMarket.address,
        ethers.utils.parseEther('1.015'),
      );

    await this.premiaOption
      .connect(seller)
      .setApprovalForAll(this.premiaMarket.address, true);

    return await this.createOrder(maker, orderOptions);
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
