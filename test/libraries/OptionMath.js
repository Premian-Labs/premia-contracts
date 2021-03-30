const { expect } = require('chai');

const fixedFromBigNumber = function (bn) {
  return bn.shl(64);
};

const fixedFromFloat = function (float) {
  const [integer = '', decimal = ''] = float.toString().split('.');
  return fixedFromBigNumber(
    ethers.BigNumber.from(`${ integer }${ decimal }`)
  ).div(
    ethers.BigNumber.from(10 ** decimal.length)
  );
};

describe('OptionMath', function () {
  let instance;

  before(async function () {
    const factory = await ethers.getContractFactory('OptionMathMock');
    instance = await factory.deploy();
    await instance.deployed();
  });

  describe('#logreturns', function () {
    it('returns the natural log returns for a given day', async function () {
      const inputs = [1].map(
        ethers.BigNumber.from
      );
      for (let bn of inputs) {
        expect(instance.callStatic.logreturns(bn, bn)).not.to.be.reverted;
      }
    });
  });

  describe('#rollingEma', function () {
    it('return the rolling ema value', async function () {
      const inputs = [1].map(
        ethers.BigNumber.from
      );
      for (let bn of inputs) {
        expect(instance.callStatic.rollingEma(bn, bn, bn)).not.to.be.reverted;
      }
    });
  });

  describe('#rollingEmaVar', function () {
    it('todo');
  });

  describe('#d1', function () {
    it('todo');
  });

  describe('#N', function () {
    it('todo');
  });

  describe('#Xt', function () {
    it('todo');
  });

  describe('#SlippageCoef', function () {
    it('todo');
  });

  describe('#bsPrice', function () {
    it('todo');
  });

  describe('#calcTradingDelta', function () {
    it('todo');
  });

  describe('#calculateCLevel', function () {
    it('todo');
  });
});
