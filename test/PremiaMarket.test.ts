import { ethers } from 'hardhat';
import { BigNumber, BigNumberish, utils } from 'ethers';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  TestErc20__factory,
  TestPremiaMarket,
  TestPremiaMarket__factory,
  TestPremiaOption,
  TestPremiaOption__factory,
} from '../contractsTyped';
import { TestErc20 } from '../contractsTyped';
import { PremiaOptionTestUtil } from './utils/PremiaOptionTestUtil';
import { IOrderCreated, IOrderCreateProps } from '../types';
import { PremiaMarketTestUtil } from './utils/PremiaMarketTestUtil';

let eth: TestErc20;
let dai: TestErc20;
let premiaOption: TestPremiaOption;
let premiaMarket: TestPremiaMarket;
let admin: SignerWithAddress;
let writer1: SignerWithAddress;
let writer2: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
const tax = 0.01;

let optionTestUtil: PremiaOptionTestUtil;
let marketTestUtil: PremiaMarketTestUtil;

describe('PremiaMarket', () => {
  beforeEach(async () => {
    [admin, writer1, writer2, user1, treasury] = await ethers.getSigners();
    const erc20Factory = new TestErc20__factory(writer1);
    eth = await erc20Factory.deploy();
    dai = await erc20Factory.deploy();

    const premiaOptionFactory = new TestPremiaOption__factory(writer1);
    premiaOption = await premiaOptionFactory.deploy(
      'dummyURI',
      eth.address,
      treasury.address,
    );

    const premiaMarketFactory = new TestPremiaMarket__factory(writer1);
    premiaMarket = await premiaMarketFactory.deploy(admin.address, eth.address);

    optionTestUtil = new PremiaOptionTestUtil({
      eth,
      dai,
      premiaOption,
      writer1,
      writer2,
      user1,
      treasury,
      tax,
    });

    marketTestUtil = new PremiaMarketTestUtil({
      eth,
      dai,
      premiaOption,
      premiaMarket,
      admin,
      writer1,
      writer2,
      user1,
      treasury,
    });

    await premiaMarket.addWhitelistedOptionContracts([premiaOption.address]);
    await premiaOption
      .connect(admin)
      .setApprovalForAll(premiaMarket.address, true);
    await eth
      .connect(admin)
      .increaseAllowance(
        premiaOption.address,
        ethers.utils.parseEther('10000'),
      );
    await dai
      .connect(admin)
      .increaseAllowance(
        premiaOption.address,
        ethers.utils.parseEther('10000'),
      );
    await eth
      .connect(admin)
      .increaseAllowance(
        premiaMarket.address,
        ethers.utils.parseEther('10000'),
      );

    await premiaOption.setToken(
      eth.address,
      utils.parseEther('1'),
      utils.parseEther('10'),
    );
  });

  describe('createOrder', () => {
    it('Should create an order', async () => {
      await optionTestUtil.mintAndWriteOption(admin, 5);
      const orderCreated = await marketTestUtil.createOrder(admin);

      expect(orderCreated.hash).to.not.be.undefined;

      let amount = await premiaMarket.amounts(orderCreated.hash);

      expect(amount).to.eq(1);
    });

    it('Should fail creating an order if option contract is not whitelisted', async () => {
      await premiaMarket.removeWhitelistedOptionContracts([
        premiaOption.address,
      ]);
      await optionTestUtil.mintAndWriteOption(admin, 5);
      await expect(marketTestUtil.createOrder(admin)).to.be.revertedWith(
        'Option contract not whitelisted',
      );
    });

    it('Should fail creating an order if option is expired', async () => {
      await optionTestUtil.mintAndWriteOption(admin, 5);
      await premiaMarket.setTimestamp(1e7);
      await expect(marketTestUtil.createOrder(admin)).to.be.revertedWith(
        'Option expired',
      );
    });
  });

  describe('isOrderValid', () => {
    describe('Sell order', () => {
      it('Should detect sell order as valid if seller still own NFTs and transfer is approved', async () => {
        await optionTestUtil.mintAndWriteOption(admin, 5);
        const order = await marketTestUtil.createOrder(admin);

        const isValid = await premiaMarket.isOrderValid(
          marketTestUtil.convertOrderCreatedToOrder(order),
        );
        expect(isValid).to.be.true;
      });

      it('Should detect sell order as invalid if seller has not approved NFT transfers', async () => {
        await optionTestUtil.mintAndWriteOption(admin, 5);
        const order = await marketTestUtil.createOrder(admin);
        await premiaOption
          .connect(admin)
          .setApprovalForAll(premiaMarket.address, false);

        const isValid = await premiaMarket.isOrderValid(
          marketTestUtil.convertOrderCreatedToOrder(order),
        );
        expect(isValid).to.be.false;
      });

      it('Should detect sell order as invalid if seller does not own NFTs anymore', async () => {
        await optionTestUtil.mintAndWriteOption(admin, 5);
        const order = await marketTestUtil.createOrder(admin);
        await premiaOption.connect(admin).cancelOption(1, 5);

        const isValid = await premiaMarket.isOrderValid(
          marketTestUtil.convertOrderCreatedToOrder(order),
        );
        expect(isValid).to.be.false;
      });

      it('Should detect sell order as invalid if amount to sell left is 0', async () => {
        await optionTestUtil.mintAndWriteOption(admin, 5);
        const order = await marketTestUtil.createOrder(admin);

        await eth.connect(writer1).mint(ethers.utils.parseEther('100'));
        await eth
          .connect(writer1)
          .increaseAllowance(
            premiaMarket.address,
            ethers.utils.parseEther('10000'),
          );
        await premiaMarket
          .connect(writer1)
          .fillOrder(marketTestUtil.convertOrderCreatedToOrder(order), 5);

        const isValid = await premiaMarket.isOrderValid(
          marketTestUtil.convertOrderCreatedToOrder(order),
        );
        expect(isValid).to.be.false;
      });
    });

    describe('Buy order', () => {
      it('Should detect buy order as valid if seller still own ERC20 and transfer is approved', async () => {
        await optionTestUtil.mintAndWriteOption(writer1, 1);

        await eth.connect(admin).mint(ethers.utils.parseEther('1.015'));
        const order = await marketTestUtil.createOrder(admin, false);

        const isValid = await premiaMarket.isOrderValid(
          marketTestUtil.convertOrderCreatedToOrder(order),
        );
        expect(isValid).to.be.true;
      });

      it('Should detect buy order as invalid if seller does not have enough to cover price + fee', async () => {
        await optionTestUtil.mintAndWriteOption(writer1, 1);

        await eth.connect(admin).mint(ethers.utils.parseEther('1.0'));
        const order = await marketTestUtil.createOrder(admin, false);

        const isValid = await premiaMarket.isOrderValid(
          marketTestUtil.convertOrderCreatedToOrder(order),
        );
        expect(isValid).to.be.false;
      });

      it('Should detect buy order as invalid if seller did not approved ERC20', async () => {
        await optionTestUtil.mintAndWriteOption(writer1, 1);

        await eth.connect(admin).mint(ethers.utils.parseEther('10'));
        await eth.connect(admin).approve(premiaMarket.address, 0);
        const order = await marketTestUtil.createOrder(admin, false);

        const isValid = await premiaMarket.isOrderValid(
          marketTestUtil.convertOrderCreatedToOrder(order),
        );
        expect(isValid).to.be.false;
      });

      it('Should detect buy order as invalid if amount to buy left is 0', async () => {
        await optionTestUtil.mintAndWriteOption(writer1, 1);

        await eth.connect(admin).mint(ethers.utils.parseEther('1.015'));
        const order = await marketTestUtil.createOrder(admin, false);

        await premiaOption
          .connect(writer1)
          .setApprovalForAll(premiaMarket.address, true);
        await premiaMarket
          .connect(writer1)
          .fillOrder(marketTestUtil.convertOrderCreatedToOrder(order), 1);

        const isValid = await premiaMarket.isOrderValid(
          marketTestUtil.convertOrderCreatedToOrder(order),
        );
        expect(isValid).to.be.false;
      });
    });
  });
});
