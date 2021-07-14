import { ethers } from 'hardhat';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  Market,
  Option,
  ERC20Mock,
  ERC20Mock__factory,
  WETH9,
  WETH9__factory,
} from '../typechain';
import { OptionTestUtil } from './utils/OptionTestUtil';
import { IOrderCreated } from '../types';
import { MarketTestUtil } from './utils/MarketTestUtil';
import { resetHardhat, setTimestampPostExpiration } from './utils/evm';
import { TEST_TOKEN_DECIMALS, ZERO_ADDRESS } from './utils/constants';
import { deployV1, IPremiaContracts } from '../scripts/utils/deployV1';
import { parseEther } from 'ethers/lib/utils';
import { getToken, mintTestToken, parseTestToken } from './utils/token';

let p: IPremiaContracts;
let weth: WETH9;
let wbtc: ERC20Mock;
let dai: ERC20Mock;
let option: Option;
let market: Market;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let user2: SignerWithAddress;
let user3: SignerWithAddress;
let feeRecipient: SignerWithAddress;
const tax = 100;
let testToken: WETH9 | ERC20Mock;

let optionTestUtil: OptionTestUtil;
let marketTestUtil: MarketTestUtil;

describe('Market', () => {
  beforeEach(async () => {
    await resetHardhat();

    [admin, user1, user2, user3, feeRecipient] = await ethers.getSigners();
    weth = await new WETH9__factory(admin).deploy();
    wbtc = await new ERC20Mock__factory(admin).deploy(
      'wBTC',
      TEST_TOKEN_DECIMALS,
    );

    p = await deployV1(admin, feeRecipient.address, true);
    await p.feeCalculator.setPremiaFeeDiscount(ZERO_ADDRESS);
    dai = p.dai as ERC20Mock;

    option = p.option;
    market = p.market;
    testToken = getToken(weth, wbtc);

    optionTestUtil = new OptionTestUtil({
      testToken,
      dai,
      option: option,
      admin: admin,
      writer1: user1,
      writer2: user2,
      user1: user3,
      feeRecipient,
      tax,
    });

    marketTestUtil = new MarketTestUtil({
      testToken,
      dai,
      option: option,
      market: market,
      admin,
      writer1: user1,
      writer2: user2,
      user1: user3,
      feeRecipient,
    });

    await option.setFeeRecipient(feeRecipient.address);
    await market.setFeeRecipient(feeRecipient.address);

    await market.addWhitelistedOptionContracts([option.address]);
    await option.connect(admin).setApprovalForAll(market.address, true);
    await testToken.connect(admin).approve(option.address, parseEther('10000'));
    await dai
      .connect(admin)
      .increaseAllowance(option.address, parseEther('10000'));
    await dai
      .connect(admin)
      .increaseAllowance(market.address, parseEther('10000'));
    await dai.connect(admin).approve(market.address, parseEther('10000'));

    await option.setTokensWhitelisted([testToken.address], true);

    await market.addWhitelistedPaymentTokens([dai.address]);
  });

  describe('createOrder', () => {
    it('should create an order', async () => {
      await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));
      const orderCreated = await marketTestUtil.createOrder(admin);

      expect(orderCreated.hash).to.not.be.undefined;

      let amount = await market.amounts(orderCreated.hash);

      expect(amount).to.eq(parseTestToken('1'));
    });

    it('should create an order for a non existing option', async () => {
      const optionDefault = optionTestUtil.getOptionDefaults();
      const tx = await market.createOrderForNewOption(
        {
          ...marketTestUtil.getDefaultOrder(user1),
        },
        1,
        {
          token: testToken.address,
          expiration: optionDefault.expiration,
          strikePrice: optionDefault.strikePrice.mul(3),
          isCall: true,
        },
      );

      const filter = market.filters.OrderCreated(
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
      const r = await market.queryFilter(filter, tx.blockHash);

      const events = r.map((el) => el.args as any as IOrderCreated);
      expect(events.length).to.eq(1);
      const orderAmount = await market.amounts(events[0].hash);
      expect(orderAmount).to.eq(1);

      const optionId = events[0].optionId;
      const optionData = await option.optionData(optionId);

      expect(optionData.token).to.eq(testToken.address);
      expect(optionData.expiration).to.eq(optionDefault.expiration);
      expect(optionData.strikePrice).to.eq(optionDefault.strikePrice.mul(3));
      expect(optionData.isCall).to.be.true;
    });

    it('should create multiple orders', async () => {
      await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));

      const newOrder = marketTestUtil.getDefaultOrder(admin);

      const tx = await market
        .connect(admin)
        .createOrders([newOrder, newOrder], [2, 3]);

      const filter = market.filters.OrderCreated(
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
      const r = await market.queryFilter(filter, tx.blockHash);

      const events = r.map((el) => el.args as any as IOrderCreated);

      expect(events.length).to.eq(2);

      const order1Amount = await market.amounts(events[0].hash);
      const order2Amount = await market.amounts(events[1].hash);

      expect(order1Amount).to.eq(2);
      expect(order2Amount).to.eq(3);
    });

    it('should fail creating an order if option contract is not whitelisted', async () => {
      await market.removeWhitelistedOptionContracts([option.address]);
      await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));
      await expect(marketTestUtil.createOrder(admin)).to.be.revertedWith(
        'Option contract not whitelisted',
      );
    });

    it('should fail creating an order if payment token is not whitelisted', async () => {
      await market.removeWhitelistedPaymentTokens([dai.address]);
      await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));
      await expect(marketTestUtil.createOrder(admin)).to.be.revertedWith(
        'Payment token not whitelisted',
      );
    });

    it('should fail creating an order if option is expired', async () => {
      await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));
      await setTimestampPostExpiration();
      await expect(marketTestUtil.createOrder(admin)).to.be.revertedWith(
        'Option expired',
      );
    });

    it('should successfully writeAndCreateOrder', async () => {
      const amount = parseTestToken('2');
      const amountWithFee = amount.add(amount.mul(tax).div(1e4));

      await mintTestToken(user1, testToken, amountWithFee);

      await testToken.connect(user1).approve(option.address, amountWithFee);
      await option.connect(user1).setApprovalForAll(market.address, true);

      const { strikePrice, expiration, token } =
        optionTestUtil.getOptionDefaults();
      await market
        .connect(user1)
        .writeAndCreateOrder(
          { token, strikePrice, expiration, amount, isCall: true },
          { ...marketTestUtil.getDefaultOrder(user1, { isBuy: false }) },
        );

      expect(await option.balanceOf(user1.address, 1)).to.eq(amount);
      expect(await testToken.balanceOf(option.address)).to.eq(amount);
      expect(await testToken.balanceOf(feeRecipient.address)).to.eq(
        amountWithFee.sub(amount),
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
        amount: parseTestToken('2'),
      });
      const order2 = await marketTestUtil.setupOrder(maker2, taker, {
        isBuy: false,
        amount: parseTestToken('2'),
      });

      const newOrder = marketTestUtil.getDefaultOrder(taker, {
        amount: parseTestToken('3'),
        isBuy: true,
      });
      let optionBalanceMaker1 = await option.balanceOf(maker1.address, 1);
      let optionBalanceMaker2 = await option.balanceOf(maker2.address, 1);
      let optionBalanceTaker = await option.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(parseTestToken('2'));
      expect(optionBalanceMaker2).to.eq(parseTestToken('2'));
      expect(optionBalanceTaker).to.eq(0);

      const tx = await market
        .connect(taker)
        .createOrderAndTryToFill(
          newOrder,
          parseTestToken('3'),
          [order1.order, order2.order],
          false,
        );

      const filter = market.filters.OrderCreated(
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
      const r = await market.queryFilter(filter, tx.blockHash);

      expect(r.length).to.eq(0);

      optionBalanceMaker1 = await option.balanceOf(maker1.address, 1);
      optionBalanceMaker2 = await option.balanceOf(maker2.address, 1);
      optionBalanceTaker = await option.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(0);
      expect(optionBalanceMaker2).to.eq(parseTestToken('1'));
      expect(optionBalanceTaker).to.eq(parseTestToken('3'));
    });

    it('should fill sell orders and create new buy order, if not enough sell order to be filled', async () => {
      const maker1 = user1;
      const maker2 = user2;
      const taker = user3;

      const order1 = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: false,
        amount: parseTestToken('2'),
      });
      const order2 = await marketTestUtil.setupOrder(maker2, taker, {
        isBuy: false,
        amount: parseTestToken('3'),
      });

      const newOrder = marketTestUtil.getDefaultOrder(taker, {
        amount: parseTestToken('7'),
        isBuy: true,
      });
      let optionBalanceMaker1 = await option.balanceOf(maker1.address, 1);
      let optionBalanceMaker2 = await option.balanceOf(maker2.address, 1);
      let optionBalanceTaker = await option.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(parseTestToken('2'));
      expect(optionBalanceMaker2).to.eq(parseTestToken('3'));
      expect(optionBalanceTaker).to.eq(0);

      const tx = await market
        .connect(taker)
        .createOrderAndTryToFill(
          newOrder,
          parseTestToken('7'),
          [order1.order, order2.order],
          false,
        );

      const filter = market.filters.OrderCreated(
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

      const r = await market.queryFilter(filter, tx.blockHash);
      expect(r.length).to.eq(1);
      const events = r.map((el) => el.args as any as IOrderCreated);
      const order = events.find((order) =>
        marketTestUtil.isOrderSame(newOrder, order),
      );

      expect(order?.amount).to.eq(parseTestToken('2'));
      expect(order?.side).to.eq(0);

      optionBalanceMaker1 = await option.balanceOf(maker1.address, 1);
      optionBalanceMaker2 = await option.balanceOf(maker2.address, 1);
      optionBalanceTaker = await option.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(0);
      expect(optionBalanceMaker2).to.eq(0);
      expect(optionBalanceTaker).to.eq(parseTestToken('5'));
    });

    it('should fill buy orders and not create sell order, if enough buy orders to be filled', async () => {
      const maker1 = user1;
      const maker2 = user2;
      const taker = user3;

      const order1 = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseTestToken('2'),
      });
      const order2 = await marketTestUtil.setupOrder(maker2, taker, {
        isBuy: true,
        amount: parseTestToken('2'),
      });

      const newOrder = marketTestUtil.getDefaultOrder(taker, {
        amount: parseTestToken('3'),
        isBuy: false,
      });

      let optionBalanceMaker1 = await option.balanceOf(maker1.address, 1);
      let optionBalanceMaker2 = await option.balanceOf(maker2.address, 1);
      let optionBalanceTaker = await option.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(0);
      expect(optionBalanceMaker2).to.eq(0);
      expect(optionBalanceTaker).to.eq(parseTestToken('4'));

      const tx = await market
        .connect(taker)
        .createOrderAndTryToFill(
          newOrder,
          parseTestToken('3'),
          [order1.order, order2.order],
          false,
        );

      const filter = market.filters.OrderCreated(
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
      const r = await market.queryFilter(filter, tx.blockHash);

      expect(r.length).to.eq(0);

      optionBalanceMaker1 = await option.balanceOf(maker1.address, 1);
      optionBalanceMaker2 = await option.balanceOf(maker2.address, 1);
      optionBalanceTaker = await option.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(parseTestToken('2'));
      expect(optionBalanceMaker2).to.eq(parseTestToken('1'));
      expect(optionBalanceTaker).to.eq(parseTestToken('1'));
    });

    it('should fill buy orders and create new sell order, if not enough buy order to be filled', async () => {
      const maker1 = user1;
      const maker2 = user2;
      const taker = user3;

      const order1 = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseTestToken('2'),
      });
      const order2 = await marketTestUtil.setupOrder(maker2, taker, {
        isBuy: true,
        amount: parseTestToken('3'),
      });

      await optionTestUtil.mintAndWriteOption(taker, parseTestToken('2'));

      const newOrder = {
        ...marketTestUtil.getDefaultOrder(taker, {
          amount: parseTestToken('7'),
          isBuy: false,
        }),
        expirationTime: 0,
        salt: 0,
      };

      let optionBalanceMaker1 = await option.balanceOf(maker1.address, 1);
      let optionBalanceMaker2 = await option.balanceOf(maker2.address, 1);
      let optionBalanceTaker = await option.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(0);
      expect(optionBalanceMaker2).to.eq(0);
      expect(optionBalanceTaker).to.eq(parseTestToken('7'));

      const tx = await market
        .connect(taker)
        .createOrderAndTryToFill(
          newOrder,
          parseTestToken('7'),
          [order1.order, order2.order],
          false,
        );

      const filter = market.filters.OrderCreated(
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

      const r = await market.queryFilter(filter, tx.blockHash);
      expect(r.length).to.eq(1);
      const events = r.map((el) => el.args as any as IOrderCreated);
      const order = events.find((order) =>
        marketTestUtil.isOrderSame(newOrder, order),
      );

      expect(order?.amount).to.eq(parseTestToken('2'));
      expect(order?.side).to.eq(1);

      optionBalanceMaker1 = await option.balanceOf(maker1.address, 1);
      optionBalanceMaker2 = await option.balanceOf(maker2.address, 1);
      optionBalanceTaker = await option.balanceOf(taker.address, 1);

      expect(optionBalanceMaker1).to.eq(parseTestToken('2'));
      expect(optionBalanceMaker2).to.eq(parseTestToken('3'));
      expect(optionBalanceTaker).to.eq(parseTestToken('2'));
    });

    it('should revert if a candidate order is same side as order', async () => {
      const maker1 = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseTestToken('2'),
      });

      const newOrder = {
        ...marketTestUtil.getDefaultOrder(taker, {
          amount: parseTestToken('7'),
          isBuy: true,
        }),
        expirationTime: 0,
        salt: 0,
      };

      await expect(
        market
          .connect(taker)
          .createOrderAndTryToFill(newOrder, 7, [order.order], false),
      ).to.be.revertedWith('Same order side');
    });

    it('should revert if a candidate order is different option contract than order', async () => {
      const maker1 = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseTestToken('2'),
      });

      const newOrder = {
        ...marketTestUtil.getDefaultOrder(taker, {
          amount: parseTestToken('7'),
          isBuy: false,
          optionContract: '0x0000000000000000000000000000000000000001',
        }),
        expirationTime: 0,
        salt: 0,
      };

      await expect(
        market
          .connect(taker)
          .createOrderAndTryToFill(newOrder, 7, [order.order], false),
      ).to.be.revertedWith('Candidate order : Diff option contract');
    });

    it('should revert if a candidate order is different optionId than order', async () => {
      const maker1 = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker1, taker, {
        isBuy: true,
        amount: parseTestToken('2'),
      });

      const newOrder = {
        ...marketTestUtil.getDefaultOrder(taker, {
          amount: parseTestToken('7'),
          isBuy: false,
          optionId: 10,
        }),
        expirationTime: 0,
        salt: 0,
      };

      await expect(
        market
          .connect(taker)
          .createOrderAndTryToFill(newOrder, 7, [order.order], false),
      ).to.be.revertedWith('Candidate order : Diff optionId');
    });
  });

  describe('isOrderValid', () => {
    it('should detect multiple orders as valid', async () => {
      await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));
      const order1 = await marketTestUtil.createOrder(admin);
      const order2 = await marketTestUtil.createOrder(admin);

      const areValid = await market.areOrdersValid([
        order1.order,
        order2.order,
      ]);
      expect(areValid.length).to.eq(2);
      expect(areValid[0]).to.be.true;
      expect(areValid[1]).to.be.true;
    });

    describe('sell order', () => {
      it('should detect sell order as valid if maker still own options and transfer is approved', async () => {
        await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));
        const order = await marketTestUtil.createOrder(admin);

        const isValid = await market.isOrderValid(order.order);
        expect(isValid).to.be.true;
      });

      it('should detect sell order as invalid if maker has not approved options transfers', async () => {
        await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));
        const order = await marketTestUtil.createOrder(admin);
        await option.connect(admin).setApprovalForAll(market.address, false);

        const isValid = await market.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect sell order as invalid if maker does not own options anymore', async () => {
        await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));
        const order = await marketTestUtil.createOrder(admin);
        await option.connect(admin).cancelOption(1, parseTestToken('5'));

        const isValid = await market.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect sell order as invalid if amount to sell left is 0', async () => {
        await optionTestUtil.mintAndWriteOption(admin, parseTestToken('5'));
        const order = await marketTestUtil.createOrder(admin);

        await dai.mint(user1.address, parseEther('100'));
        await dai.connect(user1).approve(market.address, parseEther('1000'));
        await market
          .connect(user1)
          .fillOrder(order.order, parseTestToken('5'), false);

        const isValid = await market.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });
    });

    describe('buy order', () => {
      it('should detect buy order as valid if maker still own ERC20 and transfer is approved', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseTestToken('1'));

        await dai.mint(admin.address, parseEther('1.015'));
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });

        const isValid = await market.isOrderValid(order.order);
        expect(isValid).to.be.true;
      });

      it('should detect buy order as invalid if maker does not have enough to cover price + fee', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseTestToken('1'));

        await mintTestToken(admin, testToken, parseTestToken('1'));
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });

        const isValid = await market.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect buy order as invalid if maker did not approved ERC20', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseTestToken('1'));

        await mintTestToken(admin, testToken, parseTestToken('10'));
        await testToken.connect(admin).approve(market.address, 0);
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });

        const isValid = await market.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect buy order as invalid if amount to buy left is 0', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseTestToken('1'));

        await dai.mint(admin.address, parseEther('1.015'));
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });

        await option.connect(user1).setApprovalForAll(market.address, true);
        await market
          .connect(user1)
          .fillOrder(order.order, parseTestToken('1'), false);

        const isValid = await market.isOrderValid(order.order);
        expect(isValid).to.be.false;
      });

      it('should detect order as invalid if expired', async () => {
        await optionTestUtil.mintAndWriteOption(user1, parseTestToken('1'));

        await mintTestToken(admin, testToken, parseTestToken('1.015'));
        const order = await marketTestUtil.createOrder(admin, { isBuy: true });
        await setTimestampPostExpiration();

        const isValid = await market.isOrderValid(order.order);
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
          market
            .connect(taker)
            .fillOrder(order.order, parseTestToken('1'), false),
        ).to.be.revertedWith('Order expired');
      });

      it('should fail filling order if maxAmount set is 0', async () => {
        const maker = user1;
        const taker = user2;
        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
        });

        await expect(
          market.connect(taker).fillOrder(order.order, 0, false),
        ).to.be.revertedWith('Amount must be > 0');
      });

      // it('should fail filling order if taker is specified, and someone else than taker tries to fill order', async () => {
      //   const maker = user1;
      //   const taker = user2;
      //   const order = await marketTestUtil.setupOrder(maker, taker, {
      //     taker: user3.address,
      //     isBuy: true,
      //   });
      //
      //   await expect(
      //     premiaMarket.connect(taker).fillOrder(order.order, parseEther('1')),
      //   ).to.be.revertedWith('Not specified taker');
      // });

      it('should successfully fill order if taker is specified, and the one who tried to fill', async () => {
        const maker = user1;
        const taker = user2;
        const order = await marketTestUtil.setupOrder(maker, taker, {
          taker: taker.address,
          isBuy: true,
        });

        const tx = await market
          .connect(taker)
          .fillOrder(order.order, parseTestToken('1'), false);

        // console.log(tx.gasLimit.toString());

        const optionBalanceMaker = await option.balanceOf(maker.address, 1);
        const optionBalanceTaker = await option.balanceOf(taker.address, 1);

        expect(optionBalanceMaker).to.eq(parseTestToken('1'));
        expect(optionBalanceTaker).to.eq(0);
      });

      it('should fill multiple orders', async () => {
        const maker = user1;
        const taker = user2;

        const order1 = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseTestToken('2'),
        });
        const order2 = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseTestToken('2'),
        });

        await market
          .connect(taker)
          .fillOrders([order1.order, order2.order], parseTestToken('4'), false);

        const optionBalanceMaker = await option.balanceOf(maker.address, 1);
        const optionBalanceTaker = await option.balanceOf(taker.address, 1);

        expect(optionBalanceMaker).to.eq(0);
        expect(optionBalanceTaker).to.eq(parseTestToken('4'));
      });

      it('should respect the max amount on fillOrders', async () => {
        const maker = user1;
        const taker = user2;

        const order1 = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseTestToken('2'),
        });
        const order2 = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseTestToken('2'),
        });
        const order3 = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseTestToken('10'),
        });

        await market
          .connect(taker)
          .fillOrders(
            [order1.order, order2.order, order3.order],
            parseTestToken('9'),
            false,
          );

        const optionBalanceMaker = await option.balanceOf(maker.address, 1);
        const optionBalanceTaker = await option.balanceOf(taker.address, 1);

        expect(optionBalanceMaker).to.eq(parseTestToken('5'));
        expect(optionBalanceTaker).to.eq(parseTestToken('9'));
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
      //   let amount = 20;
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

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseTestToken('2'),
        });

        let orderAmount = await market.amounts(order.hash);
        expect(orderAmount).to.eq(parseTestToken('2'));

        await market
          .connect(taker)
          .fillOrder(order.order, parseTestToken('2'), false);

        const optionBalanceMaker = await option.balanceOf(maker.address, 1);
        const optionBalanceTaker = await option.balanceOf(taker.address, 1);

        expect(optionBalanceMaker).to.eq(0);
        expect(optionBalanceTaker).to.eq(parseTestToken('2'));

        const daiBalanceMaker = await dai.balanceOf(maker.address);
        const daiBalanceTaker = await dai.balanceOf(taker.address);
        const daiBalanceFeeRecipient = await dai.balanceOf(
          feeRecipient.address,
        );

        expect(daiBalanceMaker).to.eq(parseEther('1.97'));
        expect(daiBalanceTaker).to.eq(0);
        expect(daiBalanceFeeRecipient).to.eq(parseEther('0.06'));

        orderAmount = await market.amounts(order.hash);
        expect(orderAmount).to.eq(0);
      });

      it('should fail filling sell order if maker does not have options', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
        });
        await option
          .connect(maker)
          .safeTransferFrom(
            maker.address,
            admin.address,
            1,
            parseTestToken('1'),
            '0x00',
          );
        await expect(
          market
            .connect(taker)
            .fillOrder(order.order, parseTestToken('1'), false),
        ).to.be.revertedWith('ERC1155: insufficient balances for transfer');
      });

      it('should fail filling sell order if taker does not have enough tokens', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
        });
        await dai.connect(taker).transfer(admin.address, parseEther('0.01'));
        await expect(
          market
            .connect(taker)
            .fillOrder(order.order, parseTestToken('1'), false),
        ).to.be.revertedWith('ERC20: transfer amount exceeds balance');
      });

      it('should fill sell order for 1/2 if only 1 left to sell', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: false,
          amount: parseTestToken('1'),
        });
        await market
          .connect(taker)
          .fillOrder(order.order, parseTestToken('2'), false);

        const optionBalanceMaker = await option.balanceOf(maker.address, 1);
        const optionBalanceTaker = await option.balanceOf(taker.address, 1);

        expect(optionBalanceMaker).to.eq(0);
        expect(optionBalanceTaker).to.eq(parseTestToken('1'));

        const daiBalanceMaker = await dai.balanceOf(maker.address);
        const daiBalanceTaker = await dai.balanceOf(taker.address);
        const daiBalanceFeeRecipient = await dai.balanceOf(
          feeRecipient.address,
        );

        expect(daiBalanceMaker).to.eq(parseEther('0.985'));
        expect(daiBalanceTaker).to.eq(0);
        expect(daiBalanceFeeRecipient).to.eq(parseEther('0.03'));
      });
    });

    describe('buy order', () => {
      it('should fill 2 buy orders', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
          amount: parseTestToken('2'),
        });

        let orderAmount = await market.amounts(order.hash);
        expect(orderAmount).to.eq(parseTestToken('2'));

        await market
          .connect(taker)
          .fillOrder(order.order, parseTestToken('2'), false);

        const optionBalanceMaker = await option.balanceOf(maker.address, 1);
        const optionBalanceTaker = await option.balanceOf(taker.address, 1);

        expect(optionBalanceMaker).to.eq(parseTestToken('2'));
        expect(optionBalanceTaker).to.eq(0);

        const daiBalanceMaker = await dai.balanceOf(maker.address);
        const daiBalanceTaker = await dai.balanceOf(taker.address);
        const daiBalanceFeeRecipient = await dai.balanceOf(
          feeRecipient.address,
        );

        expect(daiBalanceMaker).to.eq(0);
        expect(daiBalanceTaker).to.eq(parseEther('1.97'));
        expect(daiBalanceFeeRecipient).to.eq(parseEther('0.06'));

        orderAmount = await market.amounts(order.hash);
        expect(orderAmount).to.eq(0);
      });

      it('should fail filling buy order if maker does not have enough token', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
        });
        await dai.connect(maker).transfer(admin.address, parseEther('0.01'));
        await expect(
          market
            .connect(taker)
            .fillOrder(order.order, parseTestToken('1'), false),
        ).to.be.revertedWith('ERC20: transfer amount exceeds balance');
      });

      it('should fail filling buy order if taker does not have enough options', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
        });
        await option
          .connect(taker)
          .safeTransferFrom(
            taker.address,
            admin.address,
            1,
            parseTestToken('1'),
            '0x00',
          );
        await expect(
          market
            .connect(taker)
            .fillOrder(order.order, parseTestToken('1'), false),
        ).to.be.revertedWith('ERC1155: insufficient balances for transfer');
      });

      it('should fill buy order for 1/2 if only 1 left to buy', async () => {
        const maker = user1;
        const taker = user2;

        const order = await marketTestUtil.setupOrder(maker, taker, {
          isBuy: true,
          amount: parseTestToken('1'),
        });
        await market
          .connect(taker)
          .fillOrder(order.order, parseTestToken('2'), false);

        const optionBalanceMaker = await option.balanceOf(maker.address, 1);
        const optionBalanceTaker = await option.balanceOf(taker.address, 1);

        expect(optionBalanceMaker).to.eq(parseTestToken('1'));
        expect(optionBalanceTaker).to.eq(0);

        const daiBalanceMaker = await dai.balanceOf(maker.address);
        const daiBalanceTaker = await dai.balanceOf(taker.address);
        const daiBalanceFeeRecipient = await dai.balanceOf(
          feeRecipient.address,
        );

        expect(daiBalanceMaker).to.eq(0);
        expect(daiBalanceTaker).to.eq(parseEther('0.985'));
        expect(daiBalanceFeeRecipient).to.eq(parseEther('0.03'));
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
          .increaseAllowance(option.address, parseEther(amount.toString()));
        await option.connect(taker).setApprovalForAll(market.address, true);

        // Approve weth from maker (buyer)
        await dai.mint(maker.address, parseEther('1.015'));
        await dai
          .connect(maker)
          .approve(market.address, parseEther('10000000000000'));

        //

        const defaultOption = optionTestUtil.getOptionDefaults();

        await option.getOptionIdOrCreate(
          testToken.address,
          defaultOption.expiration,
          defaultOption.strikePrice,
          false,
        );

        const order = await marketTestUtil.createOrder(maker, {
          isBuy: true,
          amount: parseTestToken('1'),
        });

        await market.connect(taker).fillOrder(order.order, 1, true);
      });
    });
  });

  describe('cancelOrder', () => {
    it('should cancel an order', async () => {
      const maker = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseTestToken('1'),
      });

      let orderAmount = await market.amounts(order.hash);
      expect(orderAmount).to.eq(parseTestToken('1'));

      await market.connect(maker).cancelOrder(order.order);

      orderAmount = await market.amounts(order.hash);
      expect(orderAmount).to.eq(0);
    });

    it('should fail cancelling order if not called by order maker', async () => {
      const maker = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseTestToken('1'),
      });

      await expect(
        market.connect(taker).cancelOrder(order.order),
      ).to.be.revertedWith('Not order maker');
    });

    it('should fail cancelling order if order not found', async () => {
      const maker = user1;
      const taker = user2;

      const order = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseTestToken('1'),
      });

      await market
        .connect(taker)
        .fillOrder(order.order, parseTestToken('1'), false);

      await expect(
        market.connect(taker).cancelOrder(order.order),
      ).to.be.revertedWith('Order not found');
    });

    it('should cancel multiple orders', async () => {
      const maker = user1;
      const taker = user2;

      const order1 = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseTestToken('1'),
      });

      const order2 = await marketTestUtil.setupOrder(maker, taker, {
        isBuy: true,
        amount: parseTestToken('1'),
      });

      let order1Amount = await market.amounts(order1.hash);
      let order2Amount = await market.amounts(order2.hash);
      expect(order1Amount).to.eq(parseTestToken('1'));
      expect(order2Amount).to.eq(parseTestToken('1'));

      await market.connect(maker).cancelOrders([order1.order, order2.order]);

      order1Amount = await market.amounts(order1.hash);
      order2Amount = await market.amounts(order2.hash);
      expect(order1Amount).to.eq(0);
      expect(order2Amount).to.eq(0);
    });
  });

  describe('delayed writing', () => {
    it('should create a sell order with delayed writing', async () => {
      const optionDefaults = optionTestUtil.getOptionDefaults();
      await option.getOptionIdOrCreate(
        optionDefaults.token,
        optionDefaults.expiration,
        optionDefaults.strikePrice,
        optionDefaults.isCall,
      );
      const order = await marketTestUtil.createOrder(user1, {
        isDelayedWriting: true,
        isBuy: false,
        amount: parseTestToken('1'),
        pricePerUnit: parseEther('0.2'),
      });

      expect(order.order.isDelayedWriting).to.be.true;
      expect(await option.balanceOf(user1.address, 1)).to.eq(0);

      await mintTestToken(user1, testToken, parseTestToken('1.01'));
      await testToken
        .connect(user1)
        .approve(option.address, parseTestToken('1.01'));
      expect(await market.isOrderValid(order.order)).to.be.false;
      await option.connect(user1).setApprovalForAll(market.address, true);

      expect(await market.isOrderValid(order.order)).to.be.true;

      await dai.mint(user2.address, parseEther('0.203')); // 1% tx
      await dai.connect(user2).approve(market.address, parseEther('0.203'));

      // Fill the order, executing the writing of the option
      await market
        .connect(user2)
        .fillOrder(order.order, parseTestToken('0.5'), false);

      expect(await option.balanceOf(user1.address, 1)).to.eq(0);
      expect(await option.balanceOf(user2.address, 1)).to.eq(
        parseTestToken('0.5'),
      );
      expect(await testToken.balanceOf(option.address)).to.eq(
        parseTestToken('0.5'),
      );
      expect(await dai.balanceOf(user2.address)).to.eq(parseEther('0.1015'));
      expect(await dai.balanceOf(user1.address)).to.eq(parseEther('0.0985'));
      expect(await testToken.balanceOf(user1.address)).to.eq(
        parseTestToken('0.505'),
      );
      expect(await option.nbWritten(user1.address, 1)).to.eq(
        parseTestToken('0.5'),
      );
    });

    it('should never have delayed writing for a buy order', async () => {
      const optionDefaults = optionTestUtil.getOptionDefaults();
      await option.getOptionIdOrCreate(
        optionDefaults.token,
        optionDefaults.expiration,
        optionDefaults.strikePrice,
        optionDefaults.isCall,
      );
      const order = await marketTestUtil.createOrder(user1, {
        isDelayedWriting: true,
        isBuy: true,
        amount: parseTestToken('1'),
      });
      expect(order.order.isDelayedWriting).to.be.false;
    });

    it('should not allow creation of order with delayed writing is the feature is disabled', async () => {
      const optionDefaults = optionTestUtil.getOptionDefaults();
      await option.getOptionIdOrCreate(
        optionDefaults.token,
        optionDefaults.expiration,
        optionDefaults.strikePrice,
        optionDefaults.isCall,
      );
      await market.setDelayedWritingEnabled(false);
      await expect(
        market.connect(user1).createOrder(
          {
            ...marketTestUtil.getDefaultOrder(user1, {
              isDelayedWriting: true,
            }),
            expirationTime: 0,
            salt: 0,
            decimals: 0,
          },
          parseTestToken('1'),
        ),
      ).to.be.revertedWith('Delayed writing disabled');
    });
  });
});
