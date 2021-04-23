const describeBehaviorOfManagedProxyOwnable = require('@solidstate/spec/proxy/managed/ManagedProxyOwnable.behavior.js');

const describeBehaviorOfPool = require('./Pool.behavior.js');

const factory = require('../../lib/factory.js');

const SYMBOL_BASE = 'SYMBOL_BASE';
const SYMBOL_UNDERLYING = 'SYMBOL_UNDERLYING';

describe('PoolProxy', function () {
  let owner;

  let median;
  let instance;

  before(async function () {
    [owner] = await ethers.getSigners();

    const pair = await factory.Pair({ deployer: owner });
    const pool = await factory.Pool({ deployer: owner });

    const facetCuts = [
      await factory.PriceConsumer({ deployer: owner }),
      await factory.ProxyManager({ deployer: owner }),
    ].map(function (f) {
      return {
        target: f.address,
        action: 0,
        selectors: Object.keys(f.interface.functions).map(fn => f.interface.getSighash(fn)),
      };
    });

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

    const tx = await manager.deployPair(token0.address, token1.address);
    const pair = await ethers.getContractAt('Pair', (await tx.wait()).events[0].args.pair);

    instance = await ethers.getContractAt('Pool', (await pair.callStatic.getPools())[0]);
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfManagedProxyOwnable({
    deploy: () => instance,
    implementationFunction: 'getPair()',
    implementationFunctionArgs: [],
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfPool({
    deploy: () => instance,
    supply: 0,
    name: `Median Liquidity: ${ SYMBOL_UNDERLYING }/${ SYMBOL_BASE }`,
    symbol: `MED-${ SYMBOL_UNDERLYING }${ SYMBOL_BASE }`,
    decimals: 18,
  }, []);
});
