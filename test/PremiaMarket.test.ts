import { ethers } from 'hardhat';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  PremiaMarket,
  PremiaMarket__factory,
  PremiaOption,
  PremiaOption__factory,
  TestErc20,
  TestErc20__factory,
  WETH9,
  WETH9__factory,
} from '../contractsTyped';
import { PremiaOptionTestUtil } from './utils/PremiaOptionTestUtil';
import { IOrderCreated } from '../types';
import { PremiaMarketTestUtil } from './utils/PremiaMarketTestUtil';
import { resetHardhat, setTimestampPostExpiration } from './utils/evm';
import { ZERO_ADDRESS } from './utils/constants';
import { deployContracts, IPremiaContracts } from '../scripts/deployContracts';
import { parseEther } from 'ethers/lib/utils';

let p: IPremiaContracts;
let weth: WETH9;
let dai: TestErc20;
let premiaOption: PremiaOption;
let premiaMarket: PremiaMarket;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let user3: SignerWithAddress;
let feeRecipient: SignerWithAddress;
const tax = 100;

let optionTestUtil: PremiaOptionTestUtil;
let marketTestUtil: PremiaMarketTestUtil;

describe('PremiaMarket', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, user2, user3, feeRecipient] = await ethers.getSigners();
    weth = await new WETH9__factory(admin).deploy();
    dai = await new TestErc20__factory(admin).deploy();

    p = await deployContracts(admin, feeRecipient, true);
    await p.feeCalculator.setPremiaFeeDiscount(ZERO_ADDRESS);

    const premiaOptionFactory = new PremiaOption__factory(admin);
    premiaOption = await premiaOptionFactory.deploy(
      'dummyURI',
      dai.address,
      ZERO_ADDRESS,
      p.feeCalculator.address,
      ZERO_ADDRESS,
      feeRecipient.address,
    );

    const premiaMarketFactory = new PremiaMarket__factory(admin);
    premiaMarket = await premiaMarketFactory.deploy(
      p.uPremia.address,
      p.feeCalculator.address,
      admin.address,
    );

    await p.uPremia.addMinter([premiaMarket.address]);

    optionTestUtil = new PremiaOptionTestUtil({
      weth,
      dai,
      premiaOption,
      admin: admin,
      writer1: user1,
      writer2: user2,
      user1: user3,
      feeRecipient,
      tax,
    });

    marketTestUtil = new PremiaMarketTestUtil({
      weth,
      dai,
      premiaOption,
      premiaMarket,
      admin,
      writer1: user1,
      writer2: user2,
      user1: user3,
      feeRecipient,
    });

    await premiaMarket.addWhitelistedOptionContracts([premiaOption.address]);
    await premiaOption
      .connect(admin)
      .setApprovalForAll(premiaMarket.address, true);
    await weth
      .connect(admin)
      .approve(premiaOption.address, parseEther('10000'));
    await dai
      .connect(admin)
      .increaseAllowance(premiaOption.address, parseEther('10000'));
    await weth
      .connect(admin)
      .approve(premiaMarket.address, parseEther('10000'));

    await premiaOption.setToken(weth.address, parseEther('10'), false);

    await premiaMarket.addWhitelistedPaymentTokens([weth.address]);
  });

  describe('createOrder', () => {
    it('should create an order', async () => {
      await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));
      const orderCreated = await marketTestUtil.createOrder(admin);

      expect(orderCreated.hash).to.not.be.undefined;

      let amount = await premiaMarket.amounts(orderCreated.hash);

      expect(amount).to.eq(parseEther('1'));
    });

    it('should create an order for a non existing option', async () => {
      const optionDefault = optionTestUtil.getOptionDefaults();
      const tx = await premiaMarket.createOrderForNewOption(
        {
          ...marketTestUtil.getDefaultOrder(user1),
        },
        1,
        {
          token: weth.address,
          expiration: optionDefault.expiration,
          strikePrice: optionDefault.strikePrice.mul(3),
          isCall: true,
        },
      );

      const filter = premiaMarket.filters.OrderCreated(
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
      const r = await premiaMarket.queryFilter(filter, tx.blockHash);

      const events = r.map((el) => (el.args as any) as IOrderCreated);
      expect(events.length).to.eq(1);
      const orderAmount = await premiaMarket.amounts(events[0].hash);
      expect(orderAmount).to.eq(1);

      const optionId = events[0].optionId;
      const optionData = await premiaOption.optionData(optionId);

      expect(optionData.token).to.eq(weth.address);
      expect(optionData.expiration).to.eq(optionDefault.expiration);
      expect(optionData.strikePrice).to.eq(optionDefault.strikePrice.mul(3));
      expect(optionData.isCall).to.be.true;
    });

    it('should create multiple orders', async () => {
      await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));

      const newOrder = marketTestUtil.getDefaultOrder(admin);

      const tx = await premiaMarket
        .connect(admin)
        .createOrders([newOrder, newOrder], [2, 3]);

      const filter = premiaMarket.filters.OrderCreated(
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
      const r = await premiaMarket.queryFilter(filter, tx.blockHash);

      const events = r.map((el) => (el.args as any) as IOrderCreated);

      expect(events.length).to.eq(2);

      const order1Amount = await premiaMarket.amounts(events[0].hash);
      const order2Amount = await premiaMarket.amounts(events[1].hash);

      expect(order1Amount).to.eq(2);
      expect(order2Amount).to.eq(3);
    });

    it('should fail creating an order if option contract is not whitelisted', async () => {
      await premiaMarket.removeWhitelistedOptionContracts([
        premiaOption.address,
      ]);
      await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));
      await expect(marketTestUtil.createOrder(admin)).to.be.revertedWith(
        'Option contract not whitelisted',
      );
    });

    it('should fail creating an order if payment token is not whitelisted', async () => {
      await premiaMarket.removeWhitelistedPaymentTokens([weth.address]);
      await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));
      await expect(marketTestUtil.createOrder(admin)).to.be.revertedWith(
        'Payment token not whitelisted',
      );
    });

    it('should fail creating an order if option is expired', async () => {
      await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));
      await setTimestampPostExpiration();
      await expect(marketTestUtil.createOrder(admin)).to.be.revertedWith(
        'Option expired',
      );
    });
  });

  describe('createOrderAndTryToFill', () => {
    it('should fill sell orders and not create buy order, if enough sell orders to be filled', async () => {
      const maker1 = user1;
      const maker2 = user2;
      const taker = user3;

      const order1 = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: false,
        amount: parseEther('2'),
      });
      const order2 = await marketTestUtil.setupOrder(maker2, taker, {
        isBuy: false,
        amount: parseEther('2'),
      });

      const newOrder = marketTestUtil.getDefaultOrder(taker, {
        amount: parseEther('3'),
        isBuy: true,
      });
      let optionBalanceMaker1 = await premiaOption.balanceOf(maker1.address, 1);
      let optionBalanceMaker2 = await premiaOption.balanceOf(maker2.address, 1);
      let optionBalanceTaker = await premiaOption.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(parseEther('2'));
      expect(optionBalanceMaker2).to.eq(parseEther('2'));
      expect(optionBalanceTaker).to.eq(0);

      const tx = await premiaMarket
        .connect(taker)
        .createOrderAndTryToFill(newOrder, parseEther('3'), [
          order1.order,
          order2.order,
        ]);

      const filter = premiaMarket.filters.OrderCreated(
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
      const r = await premiaMarket.queryFilter(filter, tx.blockHash);

      expect(r.length).to.eq(0);

      optionBalanceMaker1 = await premiaOption.balanceOf(maker1.address, 1);
      optionBalanceMaker2 = await premiaOption.balanceOf(maker2.address, 1);
      optionBalanceTaker = await premiaOption.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(0);
      expect(optionBalanceMaker2).to.eq(parseEther('1'));
      expect(optionBalanceTaker).to.eq(parseEther('3'));
    });

    it('should fill sell orders and create new buy order, if not enough sell order to be filled', async () => {
      const maker1 = user1;
      const maker2 = user2;
      const taker = user3;

      const order1 = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: false,
        amount: parseEther('2'),
      });
      const order2 = await marketTestUtil.setupOrder(maker2, taker, {
        isBuy: false,
        amount: parseEther('3'),
      });

      const newOrder = marketTestUtil.getDefaultOrder(taker, {
        amount: parseEther('7'),
        isBuy: true,
      });
      let optionBalanceMaker1 = await premiaOption.balanceOf(maker1.address, 1);
      let optionBalanceMaker2 = await premiaOption.balanceOf(maker2.address, 1);
      let optionBalanceTaker = await premiaOption.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(parseEther('2'));
      expect(optionBalanceMaker2).to.eq(parseEther('3'));
      expect(optionBalanceTaker).to.eq(0);

      const tx = await premiaMarket
        .connect(taker)
        .createOrderAndTryToFill(newOrder, parseEther('7'), [
          order1.order,
          order2.order,
        ]);

      const filter = premiaMarket.filters.OrderCreated(
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

      const r = await premiaMarket.queryFilter(filter, tx.blockHash);
      expect(r.length).to.eq(1);
      const events = r.map((el) => (el.args as any) as IOrderCreated);
      const order = events.find((order) =>
        marketTestUtil.isOrderSame(newOrder, order),
      );

      expect(order?.amount).to.eq(parseEther('2'));
      expect(order?.side).to.eq(0);

      optionBalanceMaker1 = await premiaOption.balanceOf(maker1.address, 1);
      optionBalanceMaker2 = await premiaOption.balanceOf(maker2.address, 1);
      optionBalanceTaker = await premiaOption.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(0);
      expect(optionBalanceMaker2).to.eq(0);
      expect(optionBalanceTaker).to.eq(parseEther('5'));
    });

    it('should fill buy orders and not create sell order, if enough buy orders to be filled', async () => {
      const maker1 = user1;
      const maker2 = user2;
      const taker = user3;

      const order1 = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseEther('2'),
      });
      const order2 = await marketTestUtil.setupOrder(maker2, taker, {
        isBuy: true,
        amount: parseEther('2'),
      });

      const newOrder = marketTestUtil.getDefaultOrder(taker, {
        amount: parseEther('3'),
        isBuy: false,
      });

      let optionBalanceMaker1 = await premiaOption.balanceOf(maker1.address, 1);
      let optionBalanceMaker2 = await premiaOption.balanceOf(maker2.address, 1);
      let optionBalanceTaker = await premiaOption.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(0);
      expect(optionBalanceMaker2).to.eq(0);
      expect(optionBalanceTaker).to.eq(parseEther('4'));

      const tx = await premiaMarket
        .connect(taker)
        .createOrderAndTryToFill(newOrder, parseEther('3'), [
          order1.order,
          order2.order,
        ]);

      const filter = premiaMarket.filters.OrderCreated(
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
      const r = await premiaMarket.queryFilter(filter, tx.blockHash);

      expect(r.length).to.eq(0);

      optionBalanceMaker1 = await premiaOption.balanceOf(maker1.address, 1);
      optionBalanceMaker2 = await premiaOption.balanceOf(maker2.address, 1);
      optionBalanceTaker = await premiaOption.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(parseEther('2'));
      expect(optionBalanceMaker2).to.eq(parseEther('1'));
      expect(optionBalanceTaker).to.eq(parseEther('1'));
    });

    it('should fill buy orders and create new sell order, if not enough buy order to be filled', async () => {
      const maker1 = user1;
      const maker2 = user2;
      const taker = user3;

      const order1 = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseEther('2'),
      });
      const order2 = await marketTestUtil.setupOrder(maker2, taker, {
        isBuy: true,
        amount: parseEther('3'),
      });

      await optionTestUtil.mintAndWriteOption(taker, parseEther('2'));

      const newOrder = {
        ...marketTestUtil.getDefaultOrder(taker, {
          amount: parseEther('7'),
          isBuy: false,
        }),
        expirationTime: 0,
        salt: 0,
      };

      let optionBalanceMaker1 = await premiaOption.balanceOf(maker1.address, 1);
      let optionBalanceMaker2 = await premiaOption.balanceOf(maker2.address, 1);
      let optionBalanceTaker = await premiaOption.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(0);
      expect(optionBalanceMaker2).to.eq(0);
      expect(optionBalanceTaker).to.eq(parseEther('7'));

      const tx = await premiaMarket
        .connect(taker)
        .createOrderAndTryToFill(newOrder, parseEther('7'), [
          order1.order,
          order2.order,
        ]);

      const filter = premiaMarket.filters.OrderCreated(
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

      const r = await premiaMarket.queryFilter(filter, tx.blockHash);
      expect(r.length).to.eq(1);
      const events = r.map((el) => (el.args as any) as IOrderCreated);
      const order = events.find((order) =>
        marketTestUtil.isOrderSame(newOrder, order),
      );

      expect(order?.amount).to.eq(parseEther('2'));
      expect(order?.side).to.eq(1);

      optionBalanceMaker1 = await premiaOption.balanceOf(maker1.address, 1);
      optionBalanceMaker2 = await premiaOption.balanceOf(maker2.address, 1);
      optionBalanceTaker = await premiaOption.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(parseEther('2'));
      expect(optionBalanceMaker2).to.eq(parseEther('3'));
      expect(optionBalanceTaker).to.eq(parseEther('2'));
    });

    it('should revert if a candidate order is same side as order', async () => {
      const maker1 = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseEther('2'),
      });

      const newOrder = {
        ...marketTestUtil.getDefaultOrder(taker, {
          amount: parseEther('7'),
          isBuy: true,
        }),
        expirationTime: 0,
        salt: 0,
      };

      await expect(
        premiaMarket
          .connect(taker)
          .createOrderAndTryToFill(newOrder, 7, [order.order]),
      ).to.be.revertedWith('Same order side');
    });

    it('should revert if a candidate order is different option contract than order', async () => {
      const maker1 = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseEther('2'),
      });

      const newOrder = {
        ...marketTestUtil.getDefaultOrder(taker, {
          amount: parseEther('7'),
          isBuy: false,
          optionContract: '0x0000000000000000000000000000000000000001',
        }),
        expirationTime: 0,
        salt: 0,
      };

      await expect(
        premiaMarket
          .connect(taker)
          .createOrderAndTryToFill(newOrder, 7, [order.order]),
      ).to.be.revertedWith('Candidate order : Diff option contract');
    });

    it('should revert if a candidate order is different optionId than order', async () => {
      const maker1 = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseEther('2'),
      });

      const newOrder = {
        ...marketTestUtil.getDefaultOrder(taker, {
          amount: parseEther('7'),
          isBuy: false,
          optionId: 10,
        }),
        expirationTime: 0,
        salt: 0,
      };

      await expect(
        premiaMarket
          .connect(taker)
          .createOrderAndTryToFill(newOrder, 7, [order.order]),
      ).to.be.revertedWith('Candidate order : Diff optionId');
    });
  });

  describe('isOrderValid', () => {
    it('should detect multiple orders as valid', async () => {
      await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));
      const order1 = await marketTestUtil.createOrder(admin);
      const order2 = await marketTestUtil.createOrder(admin);

      const areValid = await premiaMarket.areOrdersValid([
        order1.order,
        order2.order,
      ]);
      expect(areValid.length).to.eq(2);
      expect(areValid[0]).to.be.true;
      expect(areValid[1]).to.be.true;
    });

    describe('sell order', () => {
      it('should detect sell order as valid if maker still own options and transfer is approved', async () => {
        await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));
        const order = await marketTestUtil.createOrder(admin);

        const isValid = await premiaMarket.isOrderValid(order.order);
        expect(isValid).to.be.true;
      });

      it('should detect sell order as invalid if maker has not approved options transfers', async () => {
        await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));
        const order = await marketTestUtil.createOrder(admin);
        await premiaOption
          .connect(admin)
          .setApprovalForAll(premiaMarket.address, false);

        const isValid = await premiaMarket.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect sell order as invalid if maker does not own options anymore', async () => {
        await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));
        const order = await marketTestUtil.createOrder(admin);
        await premiaOption.connect(admin).cancelOption(1, parseEther('5'));

        const isValid = await premiaMarket.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect sell order as invalid if amount to sell left is 0', async () => {
        await optionTestUtil.mintAndWriteOption(admin, parseEther('5'));
        const order = await marketTestUtil.createOrder(admin);

        await weth.connect(user1).deposit({ value: parseEther('100') });
        await weth
          .connect(user1)
          .approve(premiaMarket.address, parseEther('10000'));
        await premiaMarket
          .connect(user1)
          .fillOrder(order.order, parseEther('5'));

        const isValid = await premiaMarket.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });
    });

    describe('buy order', () => {
      it('should detect buy order as valid if maker still own ERC20 and transfer is approved', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseEther('1'));

        await weth.connect(admin).deposit({ value: parseEther('1.015') });
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });

        const isValid = await premiaMarket.isOrderValid(order.order);
        expect(isValid).to.be.true;
      });

      it('should detect buy order as invalid if maker does not have enough to cover price + fee', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseEther('1'));

        await weth.connect(admin).deposit({ value: parseEther('1.0') });
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });

        const isValid = await premiaMarket.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect buy order as invalid if maker did not approved ERC20', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseEther('1'));

        await weth.connect(admin).deposit({ value: parseEther('10') });
        await weth.connect(admin).approve(premiaMarket.address, 0);
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });

        const isValid = await premiaMarket.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect buy order as invalid if amount to buy left is 0', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseEther('1'));

        await weth.connect(admin).deposit({ value: parseEther('1.015') });
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });

        await premiaOption
          .connect(user1)
          .setApprovalForAll(premiaMarket.address, true);
        await premiaMarket
          .connect(user1)
          .fillOrder(order.order, parseEther('1'));

        const isValid = await premiaMarket.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect order as invalid if expired', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseEther('1'));

        await weth.connect(admin).deposit({ value: parseEther('1.015') });
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });
        await setTimestampPostExpiration();

        const isValid = await premiaMarket.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });
    });
  });

  describe('fillOrder', () => {
    describe('any side', () => {
      it('should fail filling order if order is expired', async () => {
        const maker = user1;
        const taker = user2;
        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
        });
        await setTimestampPostExpiration();

        await expect(
          premiaMarket.connect(taker).fillOrder(order.order, parseEther('1')),
        ).to.be.revertedWith('Order expired');
      });

      it('should fail filling order if maxAmount set is 0', async () => {
        const maker = user1;
        const taker = user2;
        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
        });

        await expect(
          premiaMarket.connect(taker).fillOrder(order.order, 0),
        ).to.be.revertedWith('Amount must be > 0');
      });

      it('should fail filling order if taker is specified, and someone else than taker tries to fill order', async () => {
        const maker = user1;
        const taker = user2;
        const order = await marketTestUtil.setupOrder(maker, taker, {
          taker: user3.address,
          isBuy: true,
        });

        await expect(
          premiaMarket.connect(taker).fillOrder(order.order, parseEther('1')),
        ).to.be.revertedWith('Not specified taker');
      });

      it('should successfully fill order if taker is specified, and the one who tried to fill', async () => {
        const maker = user1;
        const taker = user2;
        const order = await marketTestUtil.setupOrder(maker, taker, {
          taker: taker.address,
          isBuy: true,
        });

        const tx = await premiaMarket
          .connect(taker)
          .fillOrder(order.order, parseEther('1'));

        console.log(tx.gasLimit.toString());

        const optionBalanceMaker = await premiaOption.balanceOf(
          maker.address,
          1,
        );
        const optionBalanceTaker = await premiaOption.balanceOf(
          taker.address,
          1,
        );

        expect(optionBalanceMaker).to.eq(parseEther('1'));
        expect(optionBalanceTaker).to.eq(0);
      });

      it('should fill multiple orders', async () => {
        const maker = user1;
        const taker = user2;

        const order1 = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseEther('2'),
        });
        const order2 = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseEther('2'),
        });

        await premiaMarket
          .connect(taker)
          .fillOrders([order1.order, order2.order], parseEther('4'));

        const optionBalanceMaker = await premiaOption.balanceOf(
          maker.address,
          1,
        );
        const optionBalanceTaker = await premiaOption.balanceOf(
          taker.address,
          1,
        );

        expect(optionBalanceMaker).to.eq(0);
        expect(optionBalanceTaker).to.eq(parseEther('4'));
      });

      // it('test gas fillOrder', async () => {
      //   await p.priceProvider.setTokenPrices(
      //     [dai.address, weth.address],
      //     [parseEther('1'), parseEther('10')],
      //   );
      //
      //   const maker = user1;
      //   const taker = user2;
      //
      //   const orders: any = [];
      //
      //   let amount = 5;
      //   for (let i = 0; i < amount; i++) {
      //     const order = await marketTestUtil.setupOrder(maker, taker, {
      //       isBuy: true,
      //       amount: parseEther('2'),
      //     });
      //     orders.push(order.order);
      //   }
      //
      //   const tx = await premiaMarket
      //     .connect(taker)
      //     .fillOrders(orders, parseEther('2').mul(amount));
      //
      //   console.log(tx.gasLimit.toString());
      //
      //   const optionBalanceMaker = await premiaOption.balanceOf(
      //     maker.address,
      //     1,
      //   );
      //   const optionBalanceTaker = await premiaOption.balanceOf(
      //     taker.address,
      //     1,
      //   );
      //
      //   expect(optionBalanceMaker).to.eq(0);
      //   expect(optionBalanceTaker).to.eq(parseEther('4'));
      // });
    });

    describe('sell order', () => {
      it('should fill 2 sell orders', async () => {
        const maker = user1;
        const taker = user2;
        const feeRecipient = admin;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseEther('2'),
        });

        let orderAmount = await premiaMarket.amounts(order.hash);
        expect(orderAmount).to.eq(parseEther('2'));

        await premiaMarket
          .connect(taker)
          .fillOrder(order.order, parseEther('2'));

        const optionBalanceMaker = await premiaOption.balanceOf(
          maker.address,
          1,
        );
        const optionBalanceTaker = await premiaOption.balanceOf(
          taker.address,
          1,
        );

        expect(optionBalanceMaker).to.eq(0);
        expect(optionBalanceTaker).to.eq(parseEther('2'));

        const ethBalanceMaker = await weth.balanceOf(maker.address);
        const ethBalanceTaker = await weth.balanceOf(taker.address);
        const ethBalanceFeeRecipient = await weth.balanceOf(
          feeRecipient.address,
        );

        expect(ethBalanceMaker).to.eq(parseEther('1.97'));
        expect(ethBalanceTaker).to.eq(0);
        expect(ethBalanceFeeRecipient).to.eq(parseEther('0.06'));

        orderAmount = await premiaMarket.amounts(order.hash);
        expect(orderAmount).to.eq(0);
      });

      it('should fail filling sell order if maker does not have options', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
        });
        await premiaOption
          .connect(maker)
          .safeTransferFrom(
            maker.address,
            admin.address,
            1,
            parseEther('1'),
            '0x00',
          );
        await expect(
          premiaMarket.connect(taker).fillOrder(order.order, parseEther('1')),
        ).to.be.revertedWith('ERC1155: insufficient balance for transfer');
      });

      it('should fail filling sell order if taker does not have enough tokens', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
        });
        await weth.connect(taker).transfer(admin.address, parseEther('0.01'));
        await expect(
          premiaMarket.connect(taker).fillOrder(order.order, parseEther('1')),
        ).to.be.revertedWith('SafeERC20: low-level call failed');
      });

      it('should fill sell order for 1/2 if only 1 left to sell', async () => {
        const maker = user1;
        const taker = user2;
        const feeRecipient = admin;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseEther('1'),
        });
        await premiaMarket
          .connect(taker)
          .fillOrder(order.order, parseEther('2'));

        const optionBalanceMaker = await premiaOption.balanceOf(
          maker.address,
          1,
        );
        const optionBalanceTaker = await premiaOption.balanceOf(
          taker.address,
          1,
        );

        expect(optionBalanceMaker).to.eq(0);
        expect(optionBalanceTaker).to.eq(parseEther('1'));

        const ethBalanceMaker = await weth.balanceOf(maker.address);
        const ethBalanceTaker = await weth.balanceOf(taker.address);
        const ethBalanceFeeRecipient = await weth.balanceOf(
          feeRecipient.address,
        );

        expect(ethBalanceMaker).to.eq(parseEther('0.985'));
        expect(ethBalanceTaker).to.eq(0);
        expect(ethBalanceFeeRecipient).to.eq(parseEther('0.03'));
      });
    });

    describe('buy order', () => {
      it('should fill 2 buy orders', async () => {
        const maker = user1;
        const taker = user2;
        const feeRecipient = admin;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
          amount: parseEther('2'),
        });

        let orderAmount = await premiaMarket.amounts(order.hash);
        expect(orderAmount).to.eq(parseEther('2'));

        await premiaMarket
          .connect(taker)
          .fillOrder(order.order, parseEther('2'));

        const optionBalanceMaker = await premiaOption.balanceOf(
          maker.address,
          1,
        );
        const optionBalanceTaker = await premiaOption.balanceOf(
          taker.address,
          1,
        );

        expect(optionBalanceMaker).to.eq(parseEther('2'));
        expect(optionBalanceTaker).to.eq(0);

        const ethBalanceMaker = await weth.balanceOf(maker.address);
        const ethBalanceTaker = await weth.balanceOf(taker.address);
        const ethBalanceFeeRecipient = await weth.balanceOf(
          feeRecipient.address,
        );

        expect(ethBalanceMaker).to.eq(0);
        expect(ethBalanceTaker).to.eq(parseEther('1.97'));
        expect(ethBalanceFeeRecipient).to.eq(parseEther('0.06'));

        orderAmount = await premiaMarket.amounts(order.hash);
        expect(orderAmount).to.eq(0);
      });

      it('should fail filling buy order if maker does not have enough token', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
        });
        await weth.connect(maker).transfer(admin.address, parseEther('0.01'));
        await expect(
          premiaMarket.connect(taker).fillOrder(order.order, parseEther('1')),
        ).to.be.revertedWith('SafeERC20: low-level call failed');
      });

      it('should fail filling buy order if taker does not have enough options', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
        });
        await premiaOption
          .connect(taker)
          .safeTransferFrom(
            taker.address,
            admin.address,
            1,
            parseEther('1'),
            '0x00',
          );
        await expect(
          premiaMarket.connect(taker).fillOrder(order.order, parseEther('1')),
        ).to.be.revertedWith('ERC1155: insufficient balance for transfer');
      });

      it('should fill buy order for 1/2 if only 1 left to buy', async () => {
        const maker = user1;
        const taker = user2;
        const feeRecipient = admin;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
          amount: parseEther('1'),
        });
        await premiaMarket
          .connect(taker)
          .fillOrder(order.order, parseEther('2'));

        const optionBalanceMaker = await premiaOption.balanceOf(
          maker.address,
          1,
        );
        const optionBalanceTaker = await premiaOption.balanceOf(
          taker.address,
          1,
        );

        expect(optionBalanceMaker).to.eq(parseEther('1'));
        expect(optionBalanceTaker).to.eq(0);

        const ethBalanceMaker = await weth.balanceOf(maker.address);
        const ethBalanceTaker = await weth.balanceOf(taker.address);
        const ethBalanceFeeRecipient = await weth.balanceOf(
          feeRecipient.address,
        );

        expect(ethBalanceMaker).to.eq(0);
        expect(ethBalanceTaker).to.eq(parseEther('0.985'));
        expect(ethBalanceFeeRecipient).to.eq(parseEther('0.03'));
      });

      it('should write option + fill order', async () => {
        const maker = user1;
        const taker = user2;

        // Mint dai and approve premiaOption for taker
        const amount = parseEther('10')
          .mul(1e5 + tax * 1e5)
          .div(1e5);
        await dai.mint(taker.address, amount);
        await dai
          .connect(taker)
          .increaseAllowance(
            premiaOption.address,
            parseEther(amount.toString()),
          );
        await premiaOption
          .connect(taker)
          .setApprovalForAll(premiaMarket.address, true);

        // Approve weth from maker (buyer)
        await weth.connect(maker).deposit({ value: parseEther('1.015') });
        await weth
          .connect(maker)
          .approve(premiaMarket.address, parseEther('10000000000000'));

        //

        const defaultOption = optionTestUtil.getOptionDefaults();

        await premiaOption.getOptionIdOrCreate(
          weth.address,
          defaultOption.expiration,
          defaultOption.strikePrice,
          false,
        );

        const order = await marketTestUtil.createOrder(maker, {
          isBuy: true,
          amount: parseEther('1'),
        });

        await premiaMarket
          .connect(taker)
          .writeAndFillOrder(order.order, 1, ZERO_ADDRESS);
      });
    });
  });

  describe('cancelOrder', () => {
    it('should cancel an order', async () => {
      const maker = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseEther('1'),
      });

      let orderAmount = await premiaMarket.amounts(order.hash);
      expect(orderAmount).to.eq(parseEther('1'));

      await premiaMarket.connect(maker).cancelOrder(order.order);

      orderAmount = await premiaMarket.amounts(order.hash);
      expect(orderAmount).to.eq(0);
    });

    it('should fail cancelling order if not called by order maker', async () => {
      const maker = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseEther('1'),
      });

      await expect(
        premiaMarket.connect(taker).cancelOrder(order.order),
      ).to.be.revertedWith('Not order maker');
    });

    it('should fail cancelling order if order not found', async () => {
      const maker = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseEther('1'),
      });

      await premiaMarket.connect(taker).fillOrder(order.order, parseEther('1'));

      await expect(
        premiaMarket.connect(taker).cancelOrder(order.order),
      ).to.be.revertedWith('Order not found');
    });

    it('should cancel multiple orders', async () => {
      const maker = user1;
      const taker = user2;

      const order1 = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseEther('1'),
      });

      const order2 = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseEther('1'),
      });

      let order1Amount = await premiaMarket.amounts(order1.hash);
      let order2Amount = await premiaMarket.amounts(order2.hash);
      expect(order1Amount).to.eq(parseEther('1'));
      expect(order2Amount).to.eq(parseEther('1'));

      await premiaMarket
        .connect(maker)
        .cancelOrders([order1.order, order2.order]);

      order1Amount = await premiaMarket.amounts(order1.hash);
      order2Amount = await premiaMarket.amounts(order2.hash);
      expect(order1Amount).to.eq(0);
      expect(order2Amount).to.eq(0);
    });
  });

  describe('uPremia', () => {
    it('should reward uPremia on fillOrder for both maker and taker', async () => {
      await p.priceProvider.setTokenPrices(
        [dai.address, weth.address],
        [parseEther('1'), parseEther('10')],
      );

      const maker = user1;
      const taker = user2;
      const order = await marketTestUtil.setupOrder(maker, taker, {
        taker: taker.address,
        isBuy: true,
      });

      await premiaMarket.connect(taker).fillOrder(order.order, parseEther('1'));

      // expect(await p.uPremia.balanceOf(maker.address)).to.eq(parseEther('0.15')); // 0.015 eth fee at 1 eth = 10 usd
      // expect(await p.uPremia.balanceOf(taker.address)).to.eq(parseEther('0.15')); // 0.015 eth fee at 1 eth = 10 usd
      expect(await premiaMarket.uPremiaBalance(maker.address)).to.eq(
        parseEther('0.15'),
      ); // 0.015 eth fee at 1 eth = 10 usd
      expect(await premiaMarket.uPremiaBalance(taker.address)).to.eq(
        parseEther('0.15'),
      ); // 0.015 eth fee at 1 eth = 10 usd
    });
  });
});
