const { expect } = require('chai');
const { deployMockContract } = require('@ethereum-waffle/mock-contract');

const describeBehaviorOfERC20 = require('@solidstate/contracts/test/token/ERC20/ERC20.behavior.js');
const describeBehaviorOfERC1155Base = require('@solidstate/contracts/test/token/ERC1155/ERC1155Base.behavior.js');

const SYMBOL_BASE = 'SYMBOL_BASE';
const SYMBOL_UNDERLYING = 'SYMBOL_UNDERLYING';

describe('Pool', function () {
  let owner;

  let base;
  let underlying;

  let instance;

  before(async function () {
    [owner] = await ethers.getSigners();

    base = await deployMockContract(
      owner,
      ['function symbol () public view returns (string memory)']
    );

    underlying = await deployMockContract(
      owner,
      ['function symbol () public view returns (string memory)']
    );

    await base.mock.symbol.returns(SYMBOL_BASE);
    await underlying.mock.symbol.returns(SYMBOL_UNDERLYING);
  });

  beforeEach(async function () {
    const factory = await ethers.getContractFactory('PoolMock', owner);
    instance = await factory.deploy();
    await instance.deployed();

    await instance.connect(owner).initialize(
      base.address,
      underlying.address
    );
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfERC20({
    deploy: () => instance,
    supply: 0,
    name: `Median Liquidity: ${ SYMBOL_UNDERLYING }/${ SYMBOL_BASE }`,
    symbol: `MED-${ SYMBOL_UNDERLYING }${ SYMBOL_BASE }`,
    decimals: 18,
  });

  // eslint-disable-next-line mocha/no-setup-in-describe
  describeBehaviorOfERC1155Base({
    deploy: () => instance,
  });

  describe('__internal', function () {
    describe('#_tokenIdFor', function () {
      it('returns concatenation of maturity and strikePrice', async function () {
        const maturity = ethers.BigNumber.from(Math.floor(new Date().getTime() / 1000));
        const strikePrice = ethers.utils.parseEther((Math.random() * 1000).toString());

        expect(
          await instance.callStatic['tokenIdFor(uint192,uint64)'](
            strikePrice,
            maturity
          )
        ).to.equal(
          ethers.utils.hexConcat([
            maturity,
            ethers.utils.hexZeroPad(strikePrice, 24),
          ])
        );
      });
    });
  });
});
