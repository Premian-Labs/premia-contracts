const { expect } = require('chai');

const describeBehaviorOfPair = require('./Pair.behavior.js');

describe('Pair', function () {
  let owner;

  let instance;

  before(async function () {
    [owner] = await ethers.getSigners();
  });

  beforeEach(async function () {
    const factory = await ethers.getContractFactory('PairMock', owner);
    instance = await factory.deploy();
    await instance.deployed();
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfPair({
    deploy: () => instance,
  }, []);
});
