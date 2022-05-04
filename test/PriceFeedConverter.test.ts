import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { PriceFeedConverter, PriceFeedConverter__factory } from '../typechain';
import { resetHardhat } from './utils/evm';
import { expect } from 'chai';

let priceConverter: PriceFeedConverter;
let admin: SignerWithAddress;
let user1: SignerWithAddress;
let treasury: SignerWithAddress;

const { API_KEY_ALCHEMY } = process.env;
const jsonRpcUrl = `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`;
const blockNumber = 14051250;

describe('PriceFeedConverter', () => {
  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);

    [admin, user1, treasury] = await ethers.getSigners();

    priceConverter = await new PriceFeedConverter__factory(admin).deploy(
      '0x194a9aaf2e0b67c35915cd01101585a33fe25caa', // ALCX / ETH
      '0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419', // ETH / USD
      18,
      8,
    );
  });

  afterEach(async () => {
    await resetHardhat();
  });

  it('should convert price correctly', async () => {
    expect(await priceConverter.latestAnswer()).to.eq('19654141754');
  });
});
