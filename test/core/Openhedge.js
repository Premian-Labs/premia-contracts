const factory = require('../../lib/factory.js');

const describeBehaviorOfDiamondBase = require('@solidstate/spec/proxy/diamond/DiamondBase.behavior.js');
const describeBehaviorOfDiamondCuttable = require('@solidstate/spec/proxy/diamond/DiamondCuttable.behavior.js');
const describeBehaviorOfDiamondLoupe = require('@solidstate/spec/proxy/diamond/DiamondLoupe.behavior.js');
const describeBehaviorOfSafeOwnable = require('@solidstate/spec/access/SafeOwnable.behavior.js');

const describeBehaviorOfProxyManager = require('./ProxyManager.behavior.js');

describe('Openhedge', function () {
  let nobody, owner, nomineeOwner;

  let pair;
  let pool;

  let facetMock;

  let facets;
  let facetCuts = [];

  let instance;

  // eslint-disable-next-line mocha/no-hooks-for-single-case
  before(async function () {
    [nobody, owner, nomineeOwner] = await ethers.getSigners();

    pair = await factory.Pair({ deployer: owner });
    pool = await factory.Pool({ deployer: owner });

    facets = [
      await factory.DiamondCuttable({ deployer: owner }),
      await factory.DiamondLoupe({ deployer: owner }),
      await factory.PriceConsumer({ deployer: owner }),
      await factory.ProxyManager({ deployer: owner }),
      await factory.SafeOwnable({ deployer: owner }),
    ];

    facets.forEach(function (f) {
      Object.keys(f.interface.functions).forEach(function (fn) {
        facetCuts.push([
          f.address,
          f.interface.getSighash(fn),
        ]);
      });
    });

    const facetMockFactory = await ethers.getContractFactory('FacetMock', nobody);
    facetMock = await facetMockFactory.deploy();
    await facetMock.deployed();
  });

  // eslint-disable-next-line mocha/no-hooks-for-single-case
  beforeEach(async function () {
    instance = await factory.Openhedge({
      deployer: owner,
      facetCuts,
      pairImplementation: pair.address,
      poolImplementation: pool.address,
    });
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfDiamondBase({
    deploy: () => instance,
    facetFunction: 'owner()',
    facetFunctionArgs: [],
  }, []);

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfDiamondCuttable({
    deploy: () => instance,
    deployFacet: () => facetMock,
    getOwner: () => owner,
    getNonOwner: () => nobody,
    facetFunction: 'test()',
    facetFunctionArgs: '',
  }, []);

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfDiamondLoupe({
    deploy: () => instance,
    facetCuts,
  }, []);

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfProxyManager({
    deploy: () => instance,
    getPairImplementationAddress: () => pair.address,
    getPoolImplementationAddress: () => pool.address,
  }, []);

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfSafeOwnable({
    deploy: () => instance,
    getOwner: () => owner,
    getNomineeOwner: () => nomineeOwner,
    getNonOwner: () => nobody,
  }, []);
});
