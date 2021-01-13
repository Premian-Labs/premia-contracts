import { PremiaMarket, TestErc20, PremiaOption } from '../../contractsTyped';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumber } from 'ethers';
import { IOrderCreated, IOrderCreateProps } from '../../types';
import { ethers } from 'hardhat';
import { PremiaOptionTestUtil } from './PremiaOptionTestUtil';
import { ZERO_ADDRESS } from './constants';
import { parseEther } from 'ethers/lib/utils';

interface PremiaMarketTestUtilProps {
  eth: TestErc20;
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
  amount?: number;
  paymentToken?: string;
  optionContract?: string;
  optionId?: number;
}

export class PremiaMarketTestUtil {
  eth: TestErc20;
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
    this.eth = props.eth;
    this.dai = props.dai;
    this.premiaOption = props.premiaOption;
    this.premiaMarket = props.premiaMarket;
    this.admin = props.admin;
    this.writer1 = props.writer1;
    this.writer2 = props.writer2;
    this.user1 = props.user1;
    this.feeRecipient = props.feeRecipient;

    this.optionTestUtil = new PremiaOptionTestUtil({
      eth: this.eth,
      dai: this.dai,
      premiaOption: this.premiaOption,
      admin: this.admin,
      writer1: this.writer1,
      writer2: this.writer2,
      user1: this.user1,
      feeRecipient: this.feeRecipient,
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
      taker: orderOptions?.taker ?? ZERO_ADDRESS,
      side: Number(!orderOptions?.isBuy),
      optionContract: orderOptions?.optionContract ?? this.premiaOption.address,
      pricePerUnit: parseEther('1'),
      optionId: orderOptions?.optionId ?? 1,
      paymentToken: orderOptions?.paymentToken ?? this.eth.address,
    };

    return newOrder;
  }

  async createOrder(user: SignerWithAddress, orderOptions?: OrderOptions) {
    const newOrder = this.getDefaultOrder(user, orderOptions);
    const amount = orderOptions?.amount ?? 1;

    const tx = await this.premiaMarket.connect(user).createOrder(
      {
        ...newOrder,
        expirationTime: 0,
        salt: 0,
      },
      amount,
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

    const amount = orderOptions?.amount ?? 1;
    await this.optionTestUtil.mintAndWriteOption(seller, amount);

    await this.eth.mint(buyer.address, parseEther('1.015').mul(amount));
    await this.eth
      .connect(buyer)
      .increaseAllowance(
        this.premiaMarket.address,
        parseEther('1.015').mul(amount),
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
      paymentToken: orderCreated.paymentToken,
      pricePerUnit: orderCreated.pricePerUnit,
      expirationTime: orderCreated.expirationTime,
      salt: orderCreated.salt,
    };
  }
}
