import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const { deployMockContract } = require('@ethereum-waffle/mock-contract');
import { ethers } from 'hardhat';
import {
  ManagedProxyOwnable,
  ManagedProxyOwnable__factory,
  Median,
  Pair__factory,
  Pool,
  Pool__factory,
} from '../../typechain';

const describeBehaviorOfManagedProxyOwnable = require('@solidstate/spec/proxy/managed/ManagedProxyOwnable.behavior.js');

const describeBehaviorOfPool = require('.|/Pool.behavior.ts');

const factory = require('../../lib/factory.js');

const SYMBOL_BASE = 'SYMBOL_BASE';
const SYMBOL_UNDERLYING = 'SYMBOL_UNDERLYING';

describe('PoolProxy', function () {
  let owner: SignerWithAddress;

  let median: Median;
  let instanceProxy: ManagedProxyOwnable;
  let instancePool: Pool;

  before(async function () {
    [owner] = await ethers.getSigners();

    const pair = await factory.Pair({ deployer: owner });
    const pool = await factory.Pool({ deployer: owner });

    const facetCuts = [await factory.ProxyManager({ deployer: owner })].map(
      function (f) {
        return {
          target: f.address,
          action: 0,
          selectors: Object.keys(f.interface.functions).map((fn) =>
            f.interface.getSighash(fn),
          ),
        };
      },
    );

    median = await factory.Median({
      deployer: owner,
      facetCuts,
      pairImplementation: pair.address,
      poolImplementation: pool.address,
    });
  });

  beforeEach(async function () {
    const manager = await ethers.getContractAt('ProxyManager', median.address);

    const erc20Factory = await ethers.getContractFactory('ERC20Mock', owner);

    const token0 = await erc20Factory.deploy(SYMBOL_BASE);
    await token0.deployed();
    const token1 = await erc20Factory.deploy(SYMBOL_UNDERLYING);
    await token1.deployed();

    const oracle0 = await deployMockContract(owner, [
      'function latestRoundData () external view returns (uint80, int, uint, uint, uint80)',
      'function decimals () external view returns (uint8)',
    ]);

    const oracle1 = await deployMockContract(owner, [
      'function latestRoundData () external view returns (uint80, int, uint, uint, uint80)',
      'function decimals () external view returns (uint8)',
    ]);

    await oracle0.mock.decimals.returns(8);
    await oracle1.mock.decimals.returns(8);

    const tx = await manager.deployPair(
      token0.address,
      token1.address,
      oracle0.address,
      oracle1.address,
    );

    const pairAddress = (await tx.wait()).events[0].args.pair;
    const pair = Pair__factory.connect(pairAddress, owner);
    const pools = await pair.callStatic.getPools();

    instanceProxy = ManagedProxyOwnable__factory.connect(pools[0], owner);
    instancePool = Pool__factory.connect(pools[0], owner);
  });

  describeBehaviorOfManagedProxyOwnable({
    deploy: async () => instanceProxy,
    implementationFunction: 'getPair()',
    implementationFunctionArgs: [],
  });

  describeBehaviorOfPool(
    {
      deploy: async () => instancePool,
      supply: 0,
      name: `Median Liquidity: ${SYMBOL_UNDERLYING}/${SYMBOL_BASE}`,
      symbol: `MED-${SYMBOL_UNDERLYING}${SYMBOL_BASE}`,
      decimals: 18,
    },
    ['::ERC1155Enumerable', '#transfer', '#transferFrom'],
  );
});
