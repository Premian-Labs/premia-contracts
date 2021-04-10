const { expect } = require('chai');

const describeBehaviorOfPool = require('./Pool.behavior.js');

const fixedFromBigNumber = function (bn) {
  return bn.abs().shl(64).mul(bn.abs().div(bn));
};

const fixedFromFloat = function (float) {
  const [integer = '', decimal = ''] = float.toString().split('.');
  return fixedFromBigNumber(
    ethers.BigNumber.from(`${ integer }${ decimal }`)
  ).div(
    ethers.BigNumber.from(`1${ '0'.repeat(decimal.length) }`)
  );
};

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
        const tokenType = ethers.constants.One;
        const maturity = ethers.BigNumber.from(Math.floor(new Date().getTime() / 1000));
        const strikePrice = fixedFromFloat(Math.random() * 1000);
        const tokenId = ethers.utils.hexConcat([
          ethers.utils.hexZeroPad(tokenType, 1),
          ethers.utils.hexZeroPad(0, 7),
          ethers.utils.hexZeroPad(maturity, 8),
          ethers.utils.hexZeroPad(strikePrice, 16),
        ]);

        expect(
          await instance.callStatic['tokenIdFor(uint8,uint64,int128)'](
            tokenType,
            maturity,
            strikePrice
          )
        ).to.equal(
          tokenId
        );
      });
    });

    describe('#_parametersFor', function () {
      it('returns parameters derived from tokenId', async function () {
        const tokenType = ethers.constants.One;
        const maturity = ethers.BigNumber.from(Math.floor(new Date().getTime() / 1000));
        const strikePrice = fixedFromFloat(Math.random() * 1000);
        const tokenId = ethers.utils.hexConcat([
          ethers.utils.hexZeroPad(tokenType, 1),
          ethers.utils.hexZeroPad(0, 7),
          ethers.utils.hexZeroPad(maturity, 8),
          ethers.utils.hexZeroPad(strikePrice, 16),
        ]);

        expect(
          await instance.callStatic['parametersFor(uint256)'](tokenId)
        ).to.deep.equal(
          [
            tokenType.toNumber(),
            maturity,
            strikePrice,
          ]
        );
      });
    });
  });
});
