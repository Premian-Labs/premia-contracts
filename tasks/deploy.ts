import { task } from 'hardhat/config';

const RINKEBY_DAI = '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e';
const RINKEBY_WETH = '0xc778417e063141139fce010982780140aa0cd5ab';
const RINKEBY_DAI_PRICE_ORACLE = '0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF';
const RINKEBY_ETH_PRICE_ORACLE = '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e';

task('deploy').setAction(async function (args, hre) {
  const {
    Median__factory,
    Pair__factory,
    Pool__factory,
    ProxyManager__factory,
  } = require('../typechain');

  const [deployer] = await hre.ethers.getSigners();

  const pair = await new Pair__factory(deployer).deploy();
  const pool = await new Pool__factory(deployer).deploy(
    hre.ethers.constants.AddressZero,
  );

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

  const median = await new Median__factory(deployer).deploy(
    pair.address,
    pool.address,
  );

  await median.diamondCut(facetCuts, hre.ethers.constants.AddressZero, '0x');

  await ProxyManager__factory.connect(median.address, deployer).deployPair(RINKEBY_DAI, RINKEBY_WETH, RINKEBY_DAI_PRICE_ORACLE, RINKEBY_ETH_PRICE_ORACLE);

  console.log('Deployer: ', deployer.address);
  console.log('Pool: ', pool.address);
  console.log('Median: ', median.address);
});
