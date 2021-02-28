const { expect } = require('chai');

const describeBehaviorOfPriceConsumer = function ({ deploy }, skips) {
  describe('::PriceConsumer', function () {
    let instance;

    beforeEach(async function () {
      instance = await ethers.getContractAt('PriceConsumer', (await deploy()).address);
    });

    it('todo');
  });
};

// eslint-disable-next-line mocha/no-exports
module.exports = describeBehaviorOfPriceConsumer;
