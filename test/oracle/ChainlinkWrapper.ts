import { expect } from 'chai';
import { ethers } from 'hardhat';

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import {
  IChainlinkWrapper,
  ChainlinkWrapper__factory,
  ChainlinkWrapperProxy__factory,
} from '../../typechain';

import {
  convertPriceToBigNumberWithDecimals,
  getPriceBetweenTokens,
  validateQuote,
} from '../utils/defillama';

import { CHAINLINK_USD } from '../utils/constants';
import { resetHardhat } from '../utils/evm';

const jsonRpcUrl = `https://arb-mainnet.g.alchemy.com/v2/${process.env.API_KEY_ALCHEMY}`;
const blockNumber = 73243633; // forks from block where fee tiers have been set to target cardinality

const period = 600;

const UNISWAP_V3_FACTORY = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
const ETH_USD_ORACLE = '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612';
const ETH_USD_ORACLE_DECIMALS = 8;
const TOKEN_IN = '0x912CE59144191C1204E64559FE8253a0e49E6548';
const TOKEN_OUT = '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1';

describe('ChainlinkWrapper', () => {
  let deployer: SignerWithAddress;
  let notOwner: SignerWithAddress;
  let instance: IChainlinkWrapper;

  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', [
      { forking: { jsonRpcUrl, blockNumber } },
    ]);

    [deployer, notOwner] = await ethers.getSigners();

    const implementation = await new ChainlinkWrapper__factory(deployer).deploy(
      UNISWAP_V3_FACTORY,
      ETH_USD_ORACLE,
      TOKEN_IN,
      TOKEN_OUT,
    );

    await implementation.deployed();

    const proxy = await new ChainlinkWrapperProxy__factory(deployer).deploy(
      implementation.address,
    );

    await proxy.deployed();

    instance = ChainlinkWrapper__factory.connect(proxy.address, deployer);

    return { deployer, instance, notOwner };
  });

  afterEach(async () => {
    await resetHardhat();
  });

  describe('#constructor', () => {
    it('should set state variables', async () => {
      expect(await instance.period()).to.equal(period);

      expect(await instance.supportedFeeTiers()).to.be.deep.eq([
        100, 500, 3000, 10000,
      ]);
    });
  });

  describe('#decimals', async () => {
    it('should return correct decimals', async () => {
      expect(await instance.decimals()).to.be.eq(ETH_USD_ORACLE_DECIMALS);
    });
  });

  describe('#aggregator', async () => {
    it('should return zero address', async () => {
      expect(await instance.aggregator()).to.be.eq(
        ethers.constants.AddressZero,
      );
    });
  });

  describe('#latestAnswer', async () => {
    it('should return latest answer for pair', async () => {
      let networks = { tokenIn: 'coingecko', tokenOut: 'arbitrum' };

      const latestAnswer = await instance.latestAnswer();

      const coingeckoPrice = await getPriceBetweenTokens(
        networks,
        'arbitrum',
        CHAINLINK_USD,
      );

      const expected = convertPriceToBigNumberWithDecimals(
        coingeckoPrice,
        ETH_USD_ORACLE_DECIMALS,
      );

      validateQuote(2, latestAnswer, expected);
    });
  });

  describe('#factory', () => {
    it('should return correct UniswapV3 factory address', async () => {
      expect(await instance.factory()).to.be.eq(UNISWAP_V3_FACTORY);
    });
  });

  describe('#oracle', () => {
    it('should return correct Chainlink oracle address', async () => {
      expect(await instance.oracle()).to.be.eq(ETH_USD_ORACLE);
    });
  });

  describe('#pair', () => {
    it('should return correct token pair addresses', async () => {
      expect(await instance.pair()).to.deep.eq([TOKEN_IN, TOKEN_OUT]);
    });
  });

  describe('#period', () =>
    it('should return correct period', async () => {
      expect(await instance.period()).to.be.eq(period);
    }));

  describe('#supportedFeeTiers', () => {
    it('should return supported fee tiers', async () => {
      const feeTiers = await instance.supportedFeeTiers();
      expect(feeTiers).to.be.deep.eq([100, 500, 3000, 10000]);
    });
  });

  describe('#insertFeeTier', () => {
    it('should revert if not called by owner', async () => {
      await expect(
        instance.connect(notOwner).insertFeeTier(200),
      ).to.be.revertedWithCustomError(instance, 'Ownable__NotOwner');
    });

    it('should revert if fee tier is invalid', async () => {
      await expect(instance.insertFeeTier(15000)).to.be.revertedWithCustomError(
        instance,
        'ChainlinkWrapper__InvalidFeeTier',
      );
    });

    it('should revert if fee tier exists', async () => {
      await expect(instance.insertFeeTier(10000)).to.be.revertedWithCustomError(
        instance,
        'ChainlinkWrapper__FeeTierExists',
      );
    });
  });
});
