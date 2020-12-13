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
    premiaMarket = await premiaMarketFactory.deploy(admin.address, dai.address);

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
    await premiaOption.setApprovalForAll(premiaMarket.address, true);
    await eth.increaseAllowance(
      premiaOption.address,
      ethers.utils.parseEther('10000'),
    );
    await dai.increaseAllowance(
      premiaOption.address,
      ethers.utils.parseEther('10000'),
    );
    await eth.increaseAllowance(
      premiaMarket.address,
      ethers.utils.parseEther('10000'),
    );
  });

  it('Should create an order', async () => {
    await premiaOption.setToken(
      eth.address,
      utils.parseEther('1'),
      utils.parseEther('10'),
    );

    await optionTestUtil.mintAndWriteOption(admin, 5);

    const newOrder: IOrderCreateProps = {
      maker: admin.address,
      taker: '0x0000000000000000000000000000000000000000',
      side: 1,
      optionContract: premiaOption.address,
      pricePerUnit: ethers.utils.parseEther('1'),
      optionId: 1,
    };

    const tx = await premiaMarket.connect(admin).createOrder(
      {
        ...newOrder,
        expirationTime: 0,
        salt: 0,
      },
      1,
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
    );
    const r = await premiaMarket.queryFilter(filter, tx.blockHash);

    const events = r.map((el) => (el.args as any) as IOrderCreated);
    const orderCreated = events.find((order) =>
      marketTestUtil.isOrderSame(newOrder, order),
    );

    expect(orderCreated?.hash).to.not.be.undefined;
  });
});
