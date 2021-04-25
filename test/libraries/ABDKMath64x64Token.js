const { expect } = require('chai');

const toFixed = function(bn) {
  return bn.shl(64);
};

describe('ABDKMath64x64Token', function() {
  let instance;

  before(async function() {
    const factory = await ethers.getContractFactory('ABDKMath64x64TokenMock');
    instance = await factory.deploy();
    await instance.deployed();
  });

  describe('#toDecimals', function () {
    it('todo');
  });

  describe('#fromDecimals', function () {
    it('todo');
  });

  describe('#toWei', function () {
    it('todo');
  });

  describe('#fromWei', function () {
    it('todo');
  });
});
