import {
  PremiaMarket,
  TestErc20,
  PremiaOption,
  WETH9,
} from '../../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumber } from 'ethers';
import { IOrder, IOrderCreated, IOrderCreateProps } from '../../types';
import { ethers } from 'hardhat';
import { PremiaOptionTestUtil } from './PremiaOptionTestUtil';
import { ZERO_ADDRESS } from './constants';
import { parseEther } from 'ethers/lib/utils';

interface PremiaMarketTestUtilProps {
  weth: WETH9;
  dai: TestErc20;
  premiaOption: PremiaOption;
  premiaMarket: PremiaMarket;
  admin: SignerWithAddress;
  writer1: SignerWithAddress;
  writer2: SignerWithAddress;
  user1: SignerWithAddress;
  feeRecipient: SignerWithAddress;
}

interface OrderOptions {
  taker?: string;
  isBuy?: boolean;
  amount?: BigNumber;
  paymentToken?: string;
  optionContract?: string;
  optionId?: number;
  isDelayedWriting?: boolean;
  pricePerUnit?: BigNumber;
}

export class PremiaMarketTestUtil {
  weth: WETH9;
  dai: TestErc20;
  premiaOption: PremiaOption;
  premiaMarket: PremiaMarket;
  admin: SignerWithAddress;
  writer1: SignerWithAddress;
  writer2: SignerWithAddress;
  user1: SignerWithAddress;
  feeRecipient: SignerWithAddress;
  optionTestUtil: PremiaOptionTestUtil;

  constructor(props: PremiaMarketTestUtilProps) {
    this.weth = props.weth;
    this.dai = props.dai;
    this.premiaOption = props.premiaOption;
    this.premiaMarket = props.premiaMarket;
    this.admin = props.admin;
    this.writer1 = props.writer1;
    this.writer2 = props.writer2;
    this.user1 = props.user1;
    this.feeRecipient = props.feeRecipient;

    this.optionTestUtil = new PremiaOptionTestUtil({
      weth: this.weth,
      dai: this.dai,
      premiaOption: this.premiaOption,
      admin: this.admin,
      writer1: this.writer1,
      writer2: this.writer2,
      user1: this.user1,
      feeRecipient: this.feeRecipient,
      tax: 100,
    });
  }

  isOrderSame(order: IOrderCreateProps, orderCreated: IOrderCreated) {
    return (
      order.maker === orderCreated.maker &&
      order.side === orderCreated.side &&
      order.optionContract === orderCreated.optionContract &&
      BigNumber.from(order.pricePerUnit).eq(orderCreated.pricePerUnit) &&
      BigNumber.from(order.optionId).eq(orderCreated.optionId)
    );
  }

  getDefaultOrder(user: SignerWithAddress, orderOptions?: OrderOptions) {
    const newOrder: IOrder = {
      maker: user.address,
      side: Number(!orderOptions?.isBuy),
      isDelayedWriting: !!orderOptions?.isDelayedWriting,
      optionContract: orderOptions?.optionContract ?? this.premiaOption.address,
      pricePerUnit: orderOptions?.pricePerUnit ?? parseEther('1'),
      optionId: orderOptions?.optionId ?? 1,
      paymentToken: orderOptions?.paymentToken ?? this.weth.address,
      expirationTime: 0,
      salt: 0,
      decimals: 0,
    };

    return newOrder;
  }

  async createOrder(user: SignerWithAddress, orderOptions?: OrderOptions) {
    const newOrder = this.getDefaultOrder(user, orderOptions);
    const amount = orderOptions?.amount ?? parseEther('1');

    const tx = await this.premiaMarket.connect(user).createOrder(
      {
        ...newOrder,
        expirationTime: 0,
        salt: 0,
        decimals: 0,
      },
      amount,
    );

    // console.log(tx.gasLimit.toString());

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
      null,
      null,
    );
    const r = await this.premiaMarket.queryFilter(filter, tx.blockHash);

    const events = r.map((el) => (el.args as any) as IOrderCreated);
    const order = events.find((order) => this.isOrderSame(newOrder, order));

    if (!order) {
      throw new Error('Order not found in events');
    }

    return {
      order: this.convertOrderCreatedToOrder(order),
      hash: order.hash,
      amount: order.amount,
    };
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

    const amount = orderOptions?.amount ?? parseEther('1');
    await this.optionTestUtil.mintAndWriteOption(seller, amount);

    await this.weth
      .connect(buyer)
      .deposit({ value: amount.add(amount.mul(150).div(1e4)) });
    await this.weth
      .connect(buyer)
      .approve(this.premiaMarket.address, parseEther('10000000000000'));

    await this.premiaOption
      .connect(seller)
      .setApprovalForAll(this.premiaMarket.address, true);

    return await this.createOrder(maker, orderOptions);
  }

  convertOrderCreatedToOrder(orderCreated: IOrderCreated) {
    return {
      maker: orderCreated.maker,
      side: orderCreated.side,
      isDelayedWriting: orderCreated.isDelayedWriting,
      optionContract: orderCreated.optionContract,
      optionId: orderCreated.optionId,
      paymentToken: orderCreated.paymentToken,
      pricePerUnit: orderCreated.pricePerUnit,
      expirationTime: orderCreated.expirationTime,
      salt: orderCreated.salt,
      decimals: orderCreated.decimals,
    };
  }
}
