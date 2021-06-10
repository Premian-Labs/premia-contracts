import { task } from 'hardhat/config';
import { BigNumber, BigNumberish } from 'ethers';

const RINKEBY_DAI = '0x5592ec0cfb4dbc12d3ab100b257153436a1f0fea';
const RINKEBY_WETH = '0xc778417e063141139fce010982780140aa0cd5ab';
const RINKEBY_DAI_PRICE_ORACLE = '0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF';
const RINKEBY_ETH_PRICE_ORACLE = '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e';

const fixedFromBigNumber = function (bn: BigNumber) {
  return bn.abs().shl(64).mul(bn.abs().div(bn));
};

const fixedFromFloat = function (float: BigNumberish) {
  const [integer = '', decimal = ''] = float.toString().split('.');
  return fixedFromBigNumber(BigNumber.from(`${integer}${decimal}`)).div(
    BigNumber.from(`1${'0'.repeat(decimal.length)}`),
  );
};

task('deploy').setAction(async function (args, hre) {
  const {
    Premia__factory,
    Pool__factory,
    ProxyManager__factory,
  } = require('../typechain');

  const weth =
    hre.network.name === 'rinkeby'
      ? RINKEBY_WETH
      : hre.ethers.constants.AddressZero;

  const [deployer] = await hre.ethers.getSigners();

  const pool = await new Pool__factory(deployer).deploy(weth, deployer.address);

  const facetCuts = [await new ProxyManager__factory(deployer).deploy()].map(
    function (f) {
      return {
        target: f.address,
        action: 0,
        selectors: Object.keys(f.interface.functions).map((fn) =>
          f.interface.getSighash(fn),
        ),
      };
    },
  );

  const instance = await new Premia__factory(deployer).deploy(pool.address);

  const tx = await instance.diamondCut(
    facetCuts,
    hre.ethers.constants.AddressZero,
    '0x',
  );

  if (hre.network.name === 'rinkeby') {
    await tx.wait(1);

    await ProxyManager__factory.connect(instance.address, deployer).deployPool(
      RINKEBY_DAI,
      RINKEBY_WETH,
      RINKEBY_DAI_PRICE_ORACLE,
      RINKEBY_ETH_PRICE_ORACLE,
      fixedFromFloat(2800),
      fixedFromFloat(0.1),
      fixedFromFloat(0.2),
    );
  }

  console.log('Deployer: ', deployer.address);
  console.log('PremiaInstance: ', instance.address);
});
