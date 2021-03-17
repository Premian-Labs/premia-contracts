const { expect } = require('chai');

const describeBehaviorOfPool = require('./Pool.behavior.js');

describe('Pool', function () {
  let owner;

  let instance;

  before(async function () {
    [owner] = await ethers.getSigners();
  });

  beforeEach(async function () {
    const factory = await ethers.getContractFactory('PoolMock', owner);
    instance = await factory.deploy();
    await instance.deployed();
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfPool({
    deploy: () => instance,
    supply: 0,
    name: '',
    symbol: '',
    decimals: 0,
  }, ['#supportsInterface']);

  describe('__internal', function () {
    describe('#_tokenIdFor', function () {
      it('returns concatenation of maturity and strikePrice', async function () {
        const maturity = ethers.BigNumber.from(Math.floor(new Date().getTime() / 1000));
        const strikePrice = ethers.utils.parseEther((Math.random() * 1000).toString());

        expect(
          await instance.callStatic['tokenIdFor(uint192,uint64)'](
            strikePrice,
            maturity
          )
        ).to.equal(
          ethers.utils.hexConcat([
            maturity,
            ethers.utils.hexZeroPad(strikePrice, 24),
          ])
        );
      });
    });

    describe('#_parametersFor', function () {
      it('todo');
    });
  });
});
