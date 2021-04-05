const factory = require('../../lib/factory.js');

const describeBehaviorOfDiamond = require('@solidstate/spec/proxy/diamond/Diamond.behavior.js');

const describeBehaviorOfPriceConsumer = require('./PriceConsumer.behavior.js');
const describeBehaviorOfProxyManager = require('./ProxyManager.behavior.js');

describe('Median', function () {
  let nobody, owner, nomineeOwner;

  let pair;
  let pool;

  let facetMock;

  let facets;
  // eslint-disable-next-line no-sparse-arrays
  let facetCuts = [,];

  let instance;

  // eslint-disable-next-line mocha/no-hooks-for-single-case
  before(async function () {
    [nobody, owner, nomineeOwner] = await ethers.getSigners();

    pair = await factory.Pair({ deployer: owner });
    pool = await factory.Pool({ deployer: owner });

    facets = [
      await factory.PriceConsumer({ deployer: owner }),
      await factory.ProxyManager({ deployer: owner }),
    ];

    facets.forEach(function (f) {
      facetCuts.push({
        target: f.address,
        action: 0,
        selectors: Object.keys(f.interface.functions).map(fn => f.interface.getSighash(fn)),
      });
    });

    const facetMockFactory = await ethers.getContractFactory('FacetMock', nobody);
    facetMock = await facetMockFactory.deploy();
    await facetMock.deployed();
  });

  // eslint-disable-next-line mocha/no-hooks-for-single-case
  beforeEach(async function () {
    instance = await factory.Median({
      deployer: owner,
      facetCuts: facetCuts.slice(1),
      pairImplementation: pair.address,
      poolImplementation: pool.address,
    });

    facetCuts[0] = {
      target: instance.address,
      action: 0,
      selectors: await instance.callStatic.facetFunctionSelectors(instance.address),
    };
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfDiamond({
    deploy: () => instance,
    getOwner: () => owner,
    getNomineeOwner: () => nomineeOwner,
    getNonOwner: () => nobody,
    facetCuts,
    fallbackAddress: ethers.constants.AddressZero,
  }, []);

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfPriceConsumer({
    deploy: () => instance,
  }, []);

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfProxyManager({
    deploy: () => instance,
    getPairImplementationAddress: () => pair.address,
    getPoolImplementationAddress: () => pool.address,
  }, []);
});
