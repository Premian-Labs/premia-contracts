const { expect } = require('chai');

const describeBehaviorOfERC20 = require('@solidstate/contracts/test/token/ERC20/ERC20.behavior.js');
const describeBehaviorOfERC1155Base = require('@solidstate/contracts/test/token/ERC1155/ERC1155Base.behavior.js');

const describeBehaviorOfPool = function ({ deploy, supply, name, symbol, decimals }, skips) {
  describe('::Pool', function () {
    let instance;

    beforeEach(async function () {
      instance = await ethers.getContractAt('Pool', (await deploy()).address);
    });

    // eslint-disable-next-line mocha/no-setup-in-describe
    describeBehaviorOfERC20({
      deploy: () => instance,
      supply,
      name,
      symbol,
      decimals,
    }, skips);

    // eslint-disable-next-line mocha/no-setup-in-describe
    describeBehaviorOfERC1155Base({
      deploy: () => instance,
    }, skips);

    describe('#getPair', function () {
      it('returns pair address');
    });

    describe('#quote', function () {
      it('returns price for given option parameters');
    });

    describe('#deposit', function () {
      it('returns share tokens granted to sender');

      it('todo');
    });

    describe('#withdraw', function () {
      it('returns underlying tokens withdrawn by sender');

      it('todo');
    });

    describe('#purchase', function () {
      it('todo');
    });

    describe('#exercise', function () {
      describe('(uint256,uint192,uint64)', function () {
        it('todo');
      });

      describe('(uint256,uint256)', function () {
        it('todo');
      });
    });
  });
};

// eslint-disable-next-line mocha/no-exports
module.exports = describeBehaviorOfPool;
