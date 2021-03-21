const { expect } = require('chai');

describe('ABDKMath64x64', function() {
  let instance;

  before(async function() {
    const factory = await ethers.getContractFactory('OptionMathMock');
    instance = await factory.deploy();
    await instance.deployed();
  });

  describe('#logreturns', function () {
    it('todo');
  });

  describe('#rollingEma', function () {
    it('todo');
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
