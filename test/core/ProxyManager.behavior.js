const { expect } = require('chai');

const describeBehaviorOfProxyManager = function ({ deploy, getPairImplementationAddress, getPoolImplementationAddress }, skips) {
  describe('::ProxyManager', function () {
    let instance;

    beforeEach(async function () {
      instance = await ethers.getContractAt('ProxyManager', (await deploy()).address);
    });

    describe('#getPair', function () {
      it('todo');
    });

    describe('#deployPair', function () {
      it('todo');

      describe('reverts if', function () {
        it('todo');
      });
    });

    describe('#getPairImplementation', function () {
      it('returns address of pair implementation', async function () {
        expect(
          await instance.callStatic.getPairImplementation()
        ).to.equal(
          getPairImplementationAddress()
        );
      });
    });

    describe('#getPoolImplementation', function () {
      it('returns address of pool implementation', async function () {
        expect(
          await instance.callStatic.getPoolImplementation()
        ).to.equal(
          getPoolImplementationAddress()
        );
      });
    });
  });
};

// eslint-disable-next-line mocha/no-exports
module.exports = describeBehaviorOfProxyManager;
