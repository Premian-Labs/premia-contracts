import { ethers } from 'hardhat';
import { BigNumberish, utils } from 'ethers';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import {
  PremiaMarket,
  PremiaMarket__factory,
  TestErc20__factory,
  TestPremiaOption,
  TestPremiaOption__factory,
  TestTokenSettingsCalculator__factory,
} from '../contractsTyped';
import { TestErc20 } from '../contractsTyped';

let eth: TestErc20;
let dai: TestErc20;
let premiaOption: TestPremiaOption;
let premiaMarket: PremiaMarket;
let admin: SignerWithAddress;
let writer1: SignerWithAddress;
let writer2: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;
// const tax = 0.01;

describe('PremiaMarket', () => {
  beforeEach(async () => {
    [admin, writer1, writer2, user1, treasury] = await ethers.getSigners();
    const erc20Factory = new TestErc20__factory(writer1);
    eth = await erc20Factory.deploy();
    dai = await erc20Factory.deploy();

    const premiaOptionFactory = new TestPremiaOption__factory(writer1);
    premiaOption = await premiaOptionFactory.deploy(
      'dummyURI',
      dai.address,
      treasury.address,
    );

    const premiaMarketFactory = new PremiaMarket__factory(writer1);
    premiaMarket = await premiaMarketFactory.deploy(admin.address, eth.address);
  });
});
