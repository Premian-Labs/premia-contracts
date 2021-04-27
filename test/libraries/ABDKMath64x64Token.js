const { expect } = require('chai');

const fixedFromBigNumber = function (bn) {
  if (bn == 0) return ethers.BigNumber.from(0)
  return bn.abs().shl(64).mul(bn.abs().div(bn));
};

const bigNumberFromDecimals = function(number, decimals) {
  return fixedFromBigNumber(
    ethers.BigNumber.from(number)
  ).div(ethers.BigNumber.from(`1${'0'.repeat(decimals)}`))
}

describe('ABDKMath64x64Token', function() {
  let instance;

  before(async function() {
    const factory = await ethers.getContractFactory('ABDKMath64x64TokenMock');
    instance = await factory.deploy();
    await instance.deployed();
  });

  describe('#toDecimals', function () {
    it('converts fixed point to decimals', async function(){
      const inputs = [123456, 0, 7777777777, 1, 100, 9876543210, 09287473894, 938435].map(ethers.BigNumber.from)
      const decimals = [0, 2, 4, 6, 8, 18]

      for (let bn of inputs) {
        for (let decimal of decimals) {
          const fixed = await instance.callStatic.fromDecimals(bn, decimal)
          expect(await instance.callStatic.toDecimals(fixed, decimal)).to.be.closeTo(bn, 1)
        }
      }
    });
  });

  describe('#fromDecimals', function () {
    it('converts decimals to fixed point', async function(){
      const inputs = [123456, 0, 1, 100, 7777777777, 9876543210, 09287473894, 938435].map(ethers.BigNumber.from)
      const decimals = [0, 2, 4, 6, 8, 18]

      for (let bn of inputs) {
        for (let decimal of decimals) {
          expect(await instance.callStatic.fromDecimals(bn, decimal))
          .to.be.closeTo(bigNumberFromDecimals(bn, decimal), 1)
        }
      }
    });
  });

  describe('#toWei', function () {
    it('converts wei to eth', async function(){
      const inputs = [0, 1, 100, 123456, 777777777777, 938447477384737473847384n].map(ethers.BigNumber.from)

      for (let bn of inputs) {
        const fixed = await instance.callStatic.fromWei(bn)
        expect(await instance.callStatic.toWei(fixed)).to.be.closeTo(bn, 1)
      }
    });
  });

  describe('#fromWei', function () {
    it('converts eth to wei', async function() {
      const inputs = [0, 1, 100, 123456, 777777777777, 938447477384737473847384n].map(ethers.BigNumber.from)

      for (let bn of inputs) {
        expect(await instance.callStatic.fromWei(bn)).to.be.closeTo(bigNumberFromDecimals(bn, 18), 1)
      }
    });
  });
});
