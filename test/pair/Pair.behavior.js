const { expect } = require('chai');

const describeBehaviorOfPool = function ({ deploy }, skips) {
  describe('::Pool', function () {
    let instance;

    beforeEach(async function () {
      instance = await ethers.getContractAt('Pool', (await deploy()).address);
    });

    describe('#getPools', function () {
      it('returns pool addresses');
    });

    describe('#getVolatility', function () {
      it('todo');
    });

    describe('#update', function () {
      it('todo');
    });
  });
};

// eslint-disable-next-line mocha/no-exports
module.exports = describeBehaviorOfPool;
