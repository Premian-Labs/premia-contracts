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

  describe('#rollingAvg', function () {
    it('todo');
  });

  describe('#rollingVar', function () {
    it('todo');
  });

  describe('#p', function () {
    it('todo');
  });

  describe('#bsPrice', function () {
    it('todo');
  });

  describe('#calculateC', function () {
    it('todo');
  });

  describe('#pT', function () {
    it('todo');
  });

  describe('#approx_pT', function () {
    it('todo');
  });

  describe('#approx_Bsch', function () {
    it('todo');
  });
});
