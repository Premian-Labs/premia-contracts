import { task } from 'hardhat/config';

import {
  Median__factory,
  Pair__factory,
  Pool__factory,
  ProxyManager__factory,
} from '../typechain';

const RINKEBY_DAI = '0x5592ec0cfb4dbc12d3ab100b257153436a1f0fea';
const RINKEBY_WETH = '0xc778417e063141139fce010982780140aa0cd5ab';
const RINKEBY_DAI_PRICE_ORACLE = '0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF';
const RINKEBY_ETH_PRICE_ORACLE = '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e';

task('deploy').setAction(async function (args, hre) {
  const [deployer] = await hre.ethers.getSigners();

  const pair = await new Pair__factory(deployer).deploy();
  const pool = await new Pool__factory(deployer).deploy(RINKEBY_WETH);
  const proxyManager = await new ProxyManager__factory(deployer).deploy();

  const facetCuts = [proxyManager].map(
    function (f) {
      return {
        target: f.address,
        action: 0,
        selectors: Object.keys(f.interface.functions).map((fn) => f.interface.getSighash(fn)),
      };
    },
  );

  const median = await new Median__factory(deployer).deploy(
    pair.address,
    pool.address,
  );

  const tx = await median.diamondCut(facetCuts, hre.ethers.constants.AddressZero, '0x');

  await tx.wait(1);

  const manager = ProxyManager__factory.connect(median.address, deployer);
  
  await manager.deployPair(RINKEBY_DAI, RINKEBY_WETH, RINKEBY_DAI_PRICE_ORACLE, RINKEBY_ETH_PRICE_ORACLE);

  console.log('Deployer: ', deployer.address);
  console.log('Pool: ', pool.address);
  console.log('ProxyManager: ', proxyManager.address);
  console.log('Median: ', median.address);
});
